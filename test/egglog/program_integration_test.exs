defmodule Egglog.ProgramIntegrationTest do
  use ExUnit.Case, async: true

  alias Egglog.Program

  @math_theory """
  (datatype Math (Num i64) (Add Math Math) (Mul Math Math) (Div Math Math))
  (rewrite (Add a (Num 0)) a)
  (rewrite (Mul a (Num 1)) a)
  """

  test "loads a native program and exposes its tuple count" do
    assert {:ok, program} = Program.load(@math_theory, name: "math")
    assert {:ok, 0} = Program.num_tuples(program)
  end

  test "loaded program remains a query-local native base" do
    assert {:ok, program} = Program.load(@math_theory)
    assert {:ok, 0} = Program.num_tuples(program)

    assert {:ok, "(Num 5)"} =
             Program.extract(
               program,
               %{terms: %{"x" => "(Add (Num 5) (Num 0))"}, budget: %{rounds: 2}},
               "x"
             )

    assert {:ok, 0} = Program.num_tuples(program)
  end

  test "bang load and run variants return direct values" do
    program = Program.load!(@math_theory)

    result =
      Program.run!(program, %{
        terms: %{"goal" => "(Add (Num 1) (Num 0))"},
        budget: %{rounds: 2},
        requests: [%{type: :extract, expr: "goal"}]
      })

    assert result.status == :ok
    assert output_text(result, :extract) == "(Num 1)\n"
  end

  test "runs equality saturation and extraction through one coarse run call" do
    assert {:ok, program} = Program.load(@math_theory)

    assert {:ok, result} =
             Program.run(program, %{
               terms: %{"goal" => "(Mul (Add (Num 41) (Num 0)) (Num 1))"},
               budget: %{rounds: 4},
               requests: [%{type: :extract, expr: "goal"}, %{type: :print_size}]
             })

    assert result.status == :ok
    assert result.stats.matches > 0
    assert result.stats.iterations > 0
    assert output_text(result, :extract) == "(Num 41)\n"
    assert output_text(result, :print_all_sizes) =~ "Num"
    assert map_size(result.report.matches_per_rule) > 0
  end

  test "parsed commands can be reused for query-local runs" do
    assert {:ok, program} = Program.load(@math_theory)

    assert {:ok, commands} =
             Program.parse("""
             (let goal (Mul (Add (Num 41) (Num 0)) (Num 1)))
             (run 4)
             (extract goal)
             """)

    assert commands.count == 3
    assert {:ok, first} = Program.run(program, commands)
    assert {:ok, second} = Program.run(program, commands)

    assert output_text(first, :extract) == "(Num 41)\n"
    assert output_text(second, :extract) == "(Num 41)\n"

    assert {:ok, setup_commands} =
             Program.parse("""
             (let goal (Mul (Add (Num 41) (Num 0)) (Num 1)))
             (run 4)
             """)

    assert {:ok, "(Num 41)"} = Program.extract(program, setup_commands, "goal")
    assert {:ok, true} = Program.check(program, setup_commands, "(= goal (Num 41))")
  end

  test "check helpers expose successful and failed checks without exceptions" do
    assert {:ok, program} = Program.load(@math_theory)

    input = %{
      terms: %{"x" => "(Mul (Add (Num 1) (Num 0)) (Num 1))"},
      budget: %{rounds: 3}
    }

    assert {:ok, true} = Program.check(program, input, "(= x (Num 1))")
    assert Program.check?(program, input, "(= x (Num 1))")

    assert {:ok, false} = Program.check(program, input, "(= x (Num 2))")
    refute Program.check?(program, input, "(= x (Num 2))")
    assert :ok = Program.check_fail(program, input, "(= x (Num 2))")
  end

  test "extract helper returns native extraction text directly" do
    assert {:ok, program} = Program.load(@math_theory)

    assert {:ok, "(Num 9)"} =
             Program.extract(
               program,
               %{
                 terms: %{"x" => "(Mul (Add (Num 9) (Num 0)) (Num 1))"},
                 budget: %{rounds: 3}
               },
               "x"
             )
  end

  test "eval helper decodes primitive and e-class values from query-local runs" do
    assert {:ok, program} = Program.load(@math_theory)

    assert {:ok, %{sort: "i64", type: :integer, value: 5}} =
             Program.eval(program, "", "(+ 2 3)")

    assert {:ok, %{sort: "f64", type: :float, value: 3.5}} =
             Program.eval(program, "", "(+ 1.5 2.0)")

    assert {:ok, %{sort: "String", type: :string, value: "hello"}} =
             Program.eval(program, "", ~s("hello"))

    assert {:ok, %{sort: "bool", type: :boolean, value: true}} =
             Program.eval(program, "", "true")

    assert {:ok, %{sort: "BigInt", type: :integer_string, value: "100"}} =
             Program.eval(program, "", "(bigint 100)")

    assert {:ok, %{sort: "BigRat", type: :rational_string, value: "100/21"}} =
             Program.eval(program, "", "(bigrat (bigint 100) (bigint 21))")

    assert {:ok, %{sort: "Math", type: :value, value: value}} =
             Program.eval(
               program,
               %{terms: %{"x" => "(Add (Num 1) (Num 0))"}, budget: %{rounds: 2}},
               "x"
             )

    assert is_binary(value)
  end

  test "eval and lookup can inspect parsed command input" do
    assert {:ok, program} = Program.load("")

    assert {:ok, commands} =
             Program.parse("""
             (function score (i64) i64 :merge (max old new))
             (set (score 1) 42)
             """)

    assert {:ok, %{sort: "i64", type: :integer, value: 42}} =
             Program.lookup(program, commands, "score", ["1"])

    assert {:ok, %{sort: "i64", type: :integer, value: 42}} =
             Program.eval(program, commands, "(score 1)")
  end

  test "lookup helper evaluates keys and returns nil for missing rows" do
    theory = """
    (function score (i64) i64 :merge (max old new))
    """

    assert {:ok, program} = Program.load(theory)

    input = """
    (set (score 1) 10)
    (set (score (+ 1 1)) 20)
    """

    assert {:ok, %{sort: "i64", type: :integer, value: 10}} =
             Program.lookup(program, input, "score", ["1"])

    assert {:ok, %{sort: "i64", type: :integer, value: 20}} =
             Program.lookup(program, input, "score", ["(+ 1 1)"])

    assert {:ok, nil} = Program.lookup(program, input, "score", ["3"])
    assert {:ok, nil} = Program.lookup(program, "", "score", ["1"])
  end

  test "lookup reports arity, sort, and unknown-function errors before native table access" do
    theory = """
    (function score (i64) i64 :merge (max old new))
    """

    assert {:ok, program} = Program.load(theory)

    assert {:error, {:native_error, arity_message}} =
             Program.lookup(program, "", "score", [])

    assert arity_message =~ "expects 1 arguments"

    assert {:error, {:native_error, sort_message}} =
             Program.lookup(program, "", "score", [~s("not an integer")])

    assert sort_message =~ "expected argument"
    assert sort_message =~ "i64"

    assert {:error, {:native_error, unknown_message}} =
             Program.lookup(program, "", "missing", [])

    assert unknown_message =~ "could not find function missing"
  end

  test "factors arithmetic expressions and folds constants natively" do
    theory = """
    (datatype Math
      (Num i64)
      (Var String)
      (Add Math Math)
      (Mul Math Math))

    (rewrite (Add (Num a) (Num b)) (Num (+ a b)))
    (rewrite (Mul (Num a) (Num b)) (Num (* a b)))
    (rewrite (Add (Mul a x) (Mul b x)) (Mul (Add a b) x))
    (rewrite (Add x (Num 0)) x)
    (rewrite (Mul x (Num 1)) x)
    """

    assert {:ok, program} = Program.load(theory)

    assert {:ok, result} =
             Program.run(program, %{
               terms: %{
                 "goal" => "(Add (Mul (Num 3) (Var \"x\")) (Mul (Num 4) (Var \"x\")))"
               },
               budget: %{rounds: 5},
               requests: [%{type: :extract, expr: "goal"}]
             })

    assert output_text(result, :extract) == "(Mul (Num 7) (Var \"x\"))\n"
    assert result.stats.matches > 0
  end

  test "query-local unions trigger congruence closure in larger constructor contexts" do
    theory = """
    (datatype Term
      (A)
      (B)
      (Wrap Term)
      (Pair Term Term))
    """

    assert {:ok, program} = Program.load(theory)

    before_union =
      extract_text(
        program,
        terms: %{
          "left" => "(Pair (Wrap (A)) (A))",
          "right" => "(Pair (Wrap (B)) (B))"
        },
        requests: [%{type: :extract, expr: "left"}]
      )

    assert before_union == "(Pair (Wrap (A)) (A))\n"

    assert {:ok, after_union} =
             Program.run(program, %{
               terms: %{
                 "left" => "(Pair (Wrap (A)) (A))",
                 "right" => "(Pair (Wrap (B)) (B))"
               },
               unions: [{"(A)", "(B)"}],
               budget: %{rounds: 1},
               requests: [
                 "(check (= left right))",
                 %{type: :extract, expr: "left"}
               ]
             })

    assert after_union.status == :ok

    assert output_text(after_union, :extract) in [
             "(Pair (Wrap (A)) (A))\n",
             "(Pair (Wrap (B)) (B))\n"
           ]
  end

  test "query-local runs clone the persistent native base state" do
    assert {:ok, program} = Program.load(@math_theory)

    first =
      extract_text(
        program,
        terms: %{"x" => "(Add (Num 1) (Num 0))"},
        budget: %{rounds: 2},
        requests: [%{type: :extract, expr: "x"}]
      )

    second =
      extract_text(
        program,
        terms: %{"x" => "(Add (Num 2) (Num 0))"},
        budget: %{rounds: 2},
        requests: [%{type: :extract, expr: "x"}]
      )

    assert first == "(Num 1)\n"
    assert second == "(Num 2)\n"

    assert {:ok, 0} = Program.num_tuples(program)
  end

  test "query-local program runs are safe to use concurrently" do
    assert {:ok, program} = Program.load(@math_theory)

    results =
      1..8
      |> Task.async_stream(
        fn n ->
          Program.extract!(
            program,
            %{terms: %{"x" => "(Add (Num #{n}) (Num 0))"}, budget: %{rounds: 2}},
            "x"
          )
        end,
        max_concurrency: 4,
        timeout: 10_000
      )
      |> Enum.map(fn {:ok, value} -> value end)

    assert results == Enum.map(1..8, &"(Num #{&1})")
  end

  test "Datalog-style relations derive facts natively" do
    theory = """
    (relation edge (i64 i64))
    (relation path (i64 i64))
    (rule ((edge x y)) ((path x y)))
    (rule ((path x y) (edge y z)) ((path x z)))
    """

    assert {:ok, program} = Program.load(theory)

    assert {:ok, result} =
             Program.run(program, %{
               facts: ["(edge 1 2)", "(edge 2 3)", "(edge 3 4)"],
               budget: %{rounds: 5},
               requests: [
                 "(check (path 1 4))",
                 %{type: :print_function, name: "path", limit: 20}
               ]
             })

    assert result.stats.matches >= 5
    assert output_text(result, :print_function) =~ "(path 1 4)"
  end

  test "functions merge derived values while preserving functional dependencies" do
    theory = """
    (function dist (String) i64 :merge (min old new))
    (relation edge (String String i64))

    (rule ((edge from to weight) (= from "start"))
          ((set (dist to) weight)))

    (rule ((edge from to weight) (= known (dist from)))
          ((set (dist to) (+ known weight))))
    """

    assert {:ok, program} = Program.load(theory)

    assert {:ok, result} =
             Program.run(program, %{
               facts: [
                 "(edge \"start\" \"A\" 10)",
                 "(edge \"start\" \"B\" 3)",
                 "(edge \"B\" \"A\" 4)",
                 "(edge \"A\" \"C\" 2)",
                 "(edge \"B\" \"C\" 20)"
               ],
               budget: %{rounds: 6},
               requests: [
                 "(check (= (dist \"A\") 7))",
                 "(check (= (dist \"C\") 9))",
                 %{type: :print_function, name: "dist", limit: 10}
               ]
             })

    printed = output_text(result, :print_function)

    assert printed =~ ~s[(dist "A") -> 7]
    assert printed =~ ~s[(dist "B") -> 3]
    assert printed =~ ~s[(dist "C") -> 9]
  end

  test "guarded rewrites use egglog facts instead of Elixir-side checks" do
    theory = """
    (datatype Math (Num i64) (Div Math Math))
    (relation non-zero (Math))
    (rewrite (Div x x) (Num 1) :when ((non-zero x)))
    """

    assert {:ok, program} = Program.load(theory)

    without_guard =
      extract_text(
        program,
        terms: %{"x" => "(Div (Num 2) (Num 2))"},
        budget: %{rounds: 2},
        requests: [%{type: :extract, expr: "x"}]
      )

    with_guard =
      extract_text(
        program,
        terms: %{"x" => "(Div (Num 2) (Num 2))"},
        facts: ["(non-zero (Num 2))"],
        budget: %{rounds: 2},
        requests: [%{type: :extract, expr: "x"}]
      )

    assert without_guard == "(Div (Num 2) (Num 2))\n"
    assert with_guard == "(Num 1)\n"
  end

  test "explicit seq schedules can run analysis before guarded rewrites" do
    theory = """
    (datatype Math
      (Num i64)
      (Div Math Math))

    (relation non-zero (Math))

    (ruleset analysis)
    (ruleset simplify)

    (rule ((= e (Num n)) (!= n 0))
          ((non-zero e))
          :ruleset analysis)

    (rewrite (Div x x) (Num 1)
      :when ((non-zero x))
      :ruleset simplify)
    """

    assert {:ok, program} = Program.load(theory)

    assert {:ok, result} =
             Program.run(program, %{
               terms: %{"x" => "(Div (Num 5) (Num 5))"},
               schedule: "(seq (saturate (run analysis)) (saturate (run simplify)))",
               requests: [
                 %{type: :extract, expr: "x"},
                 %{type: :print_function, name: "non-zero", limit: 10}
               ]
             })

    assert output_text(result, :extract) == "(Num 1)\n"
    assert output_text(result, :print_function) =~ "(non-zero (Num 5))"
  end

  test "named modes map to native egglog schedules" do
    theory = """
    (datatype Math (Num i64) (Add Math Math))
    (ruleset simplify)
    (rewrite (Add a (Num 0)) a :ruleset simplify)
    """

    assert {:ok, program} =
             Program.load(theory,
               modes: %{
                 conservative: "(saturate (run simplify))",
                 noop: "(repeat 0 (run simplify))"
               }
             )

    noop =
      extract_text(
        program,
        %{terms: %{"x" => "(Add (Num 7) (Num 0))"}, requests: [%{type: :extract, expr: "x"}]},
        mode: :noop
      )

    conservative =
      extract_text(
        program,
        %{terms: %{"x" => "(Add (Num 7) (Num 0))"}, requests: [%{type: :extract, expr: "x"}]},
        mode: :conservative
      )

    assert noop == "(Add (Num 7) (Num 0))\n"
    assert conservative == "(Num 7)\n"
  end

  test "explicit schedule overrides mode and round budget" do
    assert {:ok, program} = Program.load(@math_theory)

    no_run =
      extract_text(
        program,
        %{
          terms: %{"x" => "(Add (Num 9) (Num 0))"},
          schedule: "(repeat 0 (run))",
          budget: %{rounds: 4},
          requests: [%{type: :extract, expr: "x"}]
        }
      )

    assert no_run == "(Add (Num 9) (Num 0))\n"
  end

  test "default budgets from loaded program specs drive non-trivial runs" do
    theory = %{
      program: """
      (datatype Math
        (Num i64)
        (Add Math Math))

      (rewrite (Add (Num a) (Num b)) (Num (+ a b)))
      """
    }

    assert {:ok, program} = Program.load(theory, default_budget: %{rounds: 2})

    assert {:ok, result} =
             Program.run(program, %{
               terms: %{"x" => "(Add (Num 20) (Num 22))"},
               requests: [
                 %{type: :check, expr: "(= x (Num 42))"},
                 %{type: :extract, expr: "x"},
                 %{type: :print_size}
               ]
             })

    assert output_text(result, :extract) == "(Num 42)\n"
    sizes = output_text(result, :print_all_sizes)
    assert sizes =~ "Add"
    assert sizes =~ "Num"
  end

  test "run accepts query-local source and raw commands for one-off extensions" do
    assert {:ok, program} = Program.load("")

    assert {:ok, result} =
             Program.run(program, %{
               source: """
               (datatype Expr
                 (Lit i64)
                 (Neg Expr))
               """,
               commands: [
                 "(rewrite (Neg (Neg x)) x)",
                 "(let t (Neg (Neg (Lit 8))))"
               ],
               budget: %{rounds: 2},
               requests: [
                 %{type: :check, expr: "(= t (Lit 8))"},
                 %{type: :extract, expr: "t"}
               ]
             })

    assert output_text(result, :extract) == "(Lit 8)\n"
  end

  test "direct sets seed function values used by native rules" do
    theory = """
    (function score (String) i64 :merge (max old new))
    (relation candidate (String i64))

    (rule ((candidate name amount))
          ((set (score name) amount)))
    """

    assert {:ok, program} = Program.load(theory)

    assert {:ok, result} =
             Program.run(program, %{
               sets: [{"(score \"Ada\")", "10"}],
               facts: [
                 "(candidate \"Ada\" 15)",
                 "(candidate \"Ada\" 11)"
               ],
               budget: %{rounds: 4},
               requests: [
                 %{type: :check, expr: "(= (score \"Ada\") 15)"},
                 %{type: :print_function, name: "score", limit: 10}
               ]
             })

    assert output_text(result, :print_function) =~ ~s[(score "Ada") -> 15]
  end

  test "direct sort and constructor declarations support birewrite and extraction variants" do
    theory = """
    (sort Expr)
    (constructor Var (String) Expr)
    (constructor Add (Expr Expr) Expr)

    (birewrite (Add a b) (Add b a))
    """

    assert {:ok, program} = Program.load(theory)

    assert {:ok, result} =
             Program.run(program, %{
               terms: %{"e" => "(Add (Var \"x\") (Var \"y\"))"},
               budget: %{rounds: 2},
               requests: [
                 %{type: :extract, expr: "e", variants: 3},
                 %{type: :print_size}
               ]
             })

    variants = output_text(result, :extract_variants)

    assert variants =~ ~s[(Add (Var "x") (Var "y"))]
    assert variants =~ ~s[(Add (Var "y") (Var "x"))]
    assert output_text(result, :print_all_sizes) =~ "(Add 2)"
  end

  test "constructor costs guide native extraction after saturation" do
    theory = """
    (datatype Expr
      (Var String)
      (Mul Expr Expr :cost 5)
      (Square Expr :cost 1))

    (rewrite (Mul x x) (Square x))
    """

    assert {:ok, program} = Program.load(theory)

    assert {:ok, result} =
             Program.run(program, %{
               terms: %{"x" => "(Mul (Var \"a\") (Var \"a\"))"},
               budget: %{rounds: 2},
               requests: [%{type: :extract, expr: "x"}]
             })

    assert output_text(result, :extract) == "(Square (Var \"a\"))\n"
  end

  test "optional dot snapshots expose the query-local serialized e-graph" do
    theory = """
    (datatype Term
      (A)
      (B)
      (Pair Term Term))
    """

    assert {:ok, program} = Program.load(theory)

    assert {:ok, result} =
             Program.run(
               program,
               %{
                 terms: %{"p" => "(Pair (A) (B))"},
                 unions: [{"(A)", "(B)"}],
                 budget: %{rounds: 1},
                 requests: [%{type: :check, expr: "(= (Pair (A) (A)) p)"}]
               },
               snapshot: :dot,
               snapshot_inline_leaves: 1
             )

    assert result.snapshot.format == :dot
    assert result.snapshot.text =~ "digraph"
    assert result.snapshot.text =~ "Pair"
    assert result.snapshot.omitted == ""
    assert result.stats.snapshot_nodes > 0
    assert result.stats.snapshot_classes > 0

    assert {:ok, capped} =
             Program.run(
               program,
               %{
                 terms: %{"p" => "(Pair (A) (B))"}
               },
               snapshot: :dot,
               snapshot_max_functions: 1
             )

    assert capped.snapshot.omitted =~ "Omitted:"
  end

  test "snapshot API returns plain data and can write rendered artifacts" do
    theory = """
    (datatype Term
      (A)
      (B)
      (Pair Term Term))
    """

    assert {:ok, program} = Egglog.load(theory)

    input = %{
      terms: %{"p" => "(Pair (A) (B))"},
      unions: [{"(A)", "(B)"}],
      requests: [%{type: :extract, expr: "p"}]
    }

    assert {:ok, dot_snapshot} =
             Egglog.snapshot(program, input,
               render: :dot,
               snapshot_inline_leaves: 1
             )

    assert dot_snapshot.format == :dot
    assert dot_snapshot.dot =~ "digraph"
    assert dot_snapshot.text == dot_snapshot.dot
    assert dot_snapshot.svg == nil
    assert dot_snapshot.json == nil
    assert dot_snapshot.stats.snapshot_nodes > 0
    assert output_text(dot_snapshot.result, :extract) =~ "Pair"

    assert {:ok, json_snapshot} =
             Egglog.snapshot(program, input,
               render: :json,
               snapshot_inline_leaves: 1
             )

    assert json_snapshot.format == :json
    assert json_snapshot.json == json_snapshot.text
    assert json_snapshot.dot == nil
    assert json_snapshot.svg == nil

    decoded = Jason.decode!(json_snapshot.json)
    assert is_map(decoded["nodes"])
    assert is_map(decoded["class_data"])

    assert %{nodes: nodes, classes: classes, operators: operators} =
             Egglog.Snapshot.summary(json_snapshot)

    assert nodes > 0
    assert classes > 0
    assert operators["Pair"] > 0

    dir =
      Path.join(System.tmp_dir!(), "egglog-snapshot-test-#{System.unique_integer([:positive])}")

    dot_path = Path.join(dir, "graph.dot")
    svg_path = Path.join(dir, "graph.svg")
    json_path = Path.join(dir, "graph.json")

    try do
      snapshot =
        Egglog.snapshot!(program, input,
          render: :auto,
          dot_path: dot_path,
          svg_path: svg_path,
          snapshot_inline_leaves: 1
        )

      assert File.read!(dot_path) == snapshot.dot

      if System.find_executable("dot") do
        assert snapshot.format == :svg
        assert snapshot.svg =~ "<svg"
        assert File.read!(svg_path) == snapshot.svg
      else
        assert snapshot.format == :dot
        assert snapshot.svg == nil
        assert snapshot.svg_path == nil
      end

      json_snapshot =
        Egglog.snapshot!(program, input,
          render: :json,
          json_path: json_path,
          snapshot_inline_leaves: 1
        )

      assert File.read!(json_path) == json_snapshot.json
      assert Jason.decode!(json_snapshot.json)["nodes"]
    after
      File.rm_rf(dir)
    end
  end

  test "output_limit returns a normal limit status" do
    assert {:ok, program} = Program.load(@math_theory)

    assert {:ok, result} =
             Program.run(
               program,
               %{
                 terms: %{"x" => "(Add (Num 3) (Num 0))"},
                 budget: %{rounds: 2},
                 requests: [%{type: :extract, expr: "x"}, %{type: :print_size}]
               },
               output_limit: 1
             )

    assert result.status == :limit
    assert length(result.outputs) == 1
  end

  test "invalid theory and closed programs return structured errors" do
    assert {:error, {:invalid_theory, message}} = Program.load("(definitely-not-egglog")
    assert is_binary(message)

    assert {:ok, program} = Program.load(@math_theory)
    assert :ok = Program.close(program)
    assert {:error, {:closed, _}} = Program.num_tuples(program)
    assert {:error, {:closed, _}} = Program.run(program, %{budget: %{rounds: 1}})
    assert {:error, {:closed, _}} = Program.eval(program, "", "1")
    assert {:error, {:closed, _}} = Program.lookup(program, "", "f", [])
  end

  defp extract_text(program, input, opts \\ []) do
    assert {:ok, result} = Program.run(program, Map.new(input), opts)
    output_text(result, :extract)
  end

  defp output_text(result, type) do
    result.outputs
    |> Enum.find(&(&1.type == type))
    |> Map.fetch!(:text)
  end
end
