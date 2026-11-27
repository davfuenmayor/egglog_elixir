defmodule Egglog.ExtractionTest do
  use ExUnit.Case, async: true

  alias Egglog.{Commands, EGraph, Extraction, Program}

  @theory """
  (datatype E (N i64) (Pair E E))
  """

  test "structured extraction preserves sharing, argument order and native tree cost" do
    EGraph.with_egraph(@theory, fn graph ->
      expression = "(Pair (N 1) (N 1))"
      assert EGraph.extract!(graph, expression) == expression
      data = EGraph.extract!(graph, expression, extract_format: :structured)

      assert %{roots: [%{root: root, cost: 5}], nodes: nodes} = data
      assert length(nodes) == 3
      assert {:call, "Pair", [child, child]} = Enum.at(nodes, root)
      assert {:call, "N", [_literal]} = Enum.at(nodes, child)

      assert Extraction.term(data) ==
               {:call, "Pair",
                [
                  {:call, "N", [{:literal, 1}]},
                  {:call, "N", [{:literal, 1}]}
                ]}

      ordered = EGraph.extract!(graph, "(Pair (N 1) (N 2))", extract_format: :structured)
      assert {:call, "Pair", [left, right]} = Extraction.term(ordered)
      assert left == {:call, "N", [{:literal, 1}]}
      assert right == {:call, "N", [{:literal, 2}]}
    end)
  end

  test "Program and facade retain clone-local inputs, parsed inputs and output limits" do
    Program.with_program(@theory, fn program ->
      input = Commands.parse!("(let x (N 42))")
      data = Egglog.extract!(program, input, "x", %{"extract_format" => "structured"})
      assert Extraction.term(data) == {:call, "N", [{:literal, 42}]}
      assert Program.num_tuples(program) == {:ok, 0}
      assert {:error, _} = Program.extract(program, "", "x", extract_format: :structured)

      assert {:error, {:invalid_option, _}} =
               Program.extract(program, "", "1", extract_format: :structured, output_limit: 1)
    end)
  end

  test "structured extraction executes query-local input exactly once" do
    source = "(function counter () i64 :merge (+ old new)) (set (counter) 0)"

    Program.with_program(source, fn program ->
      data =
        Program.extract!(program, "(set (counter) 1)", "(counter)", extract_format: :structured)

      assert Extraction.term(data) == {:literal, 1}
      assert Program.eval!(program, "", "(counter)").value == 0
    end)
  end

  test "variants retain native roots and costs" do
    Program.with_program(@theory, fn program ->
      data =
        Program.extract!(program, "(union (N 1) (N 2))", "(N 1)",
          variants: 2,
          extract_format: :structured
        )

      assert [%{cost: 2}, %{cost: 2}] = data.roots

      assert MapSet.new(for index <- 0..1, do: Extraction.term(data, index)) ==
               MapSet.new([{:call, "N", [{:literal, 1}]}, {:call, "N", [{:literal, 2}]}])

      assert_raise Enum.OutOfBoundsError, fn -> Extraction.term(data, 2) end
    end)
  end

  test "literal values come from the native AST, including escaped Unicode strings" do
    Program.with_program("", fn program ->
      for {expression, value} <- [
            {"9223372036854775807", 9_223_372_036_854_775_807},
            {"-9223372036854775808", -9_223_372_036_854_775_808},
            {"1.25", 1.25},
            {"inf", :infinity},
            {"-inf", :negative_infinity},
            {"NaN", :nan},
            {"true", true},
            {"false", false},
            {"()", nil},
            {~S("a\"b\nλ"), "a\"b\nλ"}
          ] do
        data = Program.extract!(program, "", expression, extract_format: :structured)
        assert Extraction.term(data) == {:literal, value}
        assert [%{cost: 1}] = data.roots
      end
    end)
  end

  test "container roots retain native structure and container cost semantics" do
    Program.with_program("(sort IntVec (Vec i64))", fn program ->
      data = Program.extract!(program, "", "(vec-of 1 1)", extract_format: :structured)
      assert Extraction.term(data) == {:call, "vec-of", [{:literal, 1}, {:literal, 1}]}
      assert [%{cost: 2}] = data.roots
      assert length(data.nodes) == 2
    end)
  end

  test "native constructor costs remain authoritative" do
    source = "(datatype E (N i64 :cost 10))"

    EGraph.with_egraph(
      source,
      fn graph ->
        data = EGraph.extract!(graph, "(N 1)", extract_format: :structured)
        assert [%{cost: 11}] = data.roots
        assert Extraction.term(data) == {:call, "N", [{:literal, 1}]}
      end
    )
  end

  test "variant costs respect constructor overrides rather than counting DAG nodes" do
    source = """
    (datatype E (N i64 :cost 7) (Cheap E :cost 1) (Expensive E :cost 100))
    (union (Cheap (N 1)) (Expensive (N 1)))
    """

    for proofs <- [false, true] do
      EGraph.with_egraph(
        source,
        fn graph ->
          data = EGraph.extract!(graph, "(Cheap (N 1))", variants: 2, extract_format: :structured)
          assert Enum.map(data.roots, & &1.cost) == [9, 108]
          assert length(data.nodes) == 4
          assert {:call, "Cheap", [child]} = Enum.at(data.nodes, hd(data.roots).root)
          assert {:call, "Expensive", [^child]} = Enum.at(data.nodes, List.last(data.roots).root)

          assert EGraph.extract!(graph, "(Cheap (N 1))", variants: 2) ==
                   "(\n   (Cheap (N 1))\n   (Expensive (N 1))\n)"
        end,
        proofs: proofs
      )
    end
  end

  test "large shared terms retain a small DAG without generating expanded text" do
    input = ["(let x0 (N 1))"] ++ for(n <- 1..40, do: "(let x#{n} (Pair x#{n - 1} x#{n - 1}))")

    Program.with_program(@theory, fn program ->
      data = Program.extract!(program, input, "x40", extract_format: :structured)
      assert length(data.nodes) == 42
      assert [%{cost: cost}] = data.roots
      assert cost == 3 * Integer.pow(2, 40) - 1
    end)
  end

  test "proof-enabled Program extracts exact variant costs from a clone" do
    source = "(datatype E (Cheap :cost 3) (Expensive :cost 19))"

    Program.with_program(
      source,
      fn program ->
        data =
          Program.extract!(program, "(union (Cheap) (Expensive))", "(Cheap)",
            extract_format: :structured,
            variants: 2
          )

        assert [%{cost: 3}, %{cost: 19}] = data.roots
        assert Extraction.term(data, 1) == {:call, "Expensive", []}

        base = Program.extract!(program, "", "(Cheap)", extract_format: :structured, variants: 2)
        assert [%{cost: 3}] = base.roots
        best = Program.extract!(program, "", "(Cheap)", extract_format: :structured)
        assert [%{cost: 3}] = best.roots
      end,
      proofs: true
    )
  end

  test "unextractable best terms remain errors while empty variants retain no roots" do
    Program.with_program("(datatype E (Hidden :unextractable))", fn program ->
      assert {:error, {:native_error, _}} =
               Program.extract(program, "", "(Hidden)", extract_format: :structured)

      data = Program.extract!(program, "", "(Hidden)", variants: 1, extract_format: :structured)
      assert data.roots == []
      assert_raise Enum.OutOfBoundsError, fn -> Extraction.term(data) end
    end)
  end

  test "invalid formats fail before mutation, and closed handles retain their error" do
    {:ok, graph} = EGraph.new(@theory)
    on_exit(fn -> EGraph.close(graph) end)
    assert {:error, {:invalid_option, _}} = EGraph.extract(graph, "(N 99)", extract_format: :json)
    assert EGraph.num_tuples(graph) == {:ok, 0}
    :ok = EGraph.close(graph)
    assert {:error, {:closed, _}} = EGraph.extract(graph, "(N 99)", extract_format: :structured)
  end
end
