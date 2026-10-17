defmodule Egglog.BoundaryTest do
  use ExUnit.Case, async: true

  doctest Egglog

  alias Egglog.{Commands, EGraph, Program}

  test "invalid timeouts are rejected before native input can mutate a graph" do
    EGraph.with_egraph(fn graph ->
      for timeout <- [0, -1, nil, :infinity, "bad", 4_294_967_296] do
        assert {:error, {:invalid_option, _}} = EGraph.snapshot(graph, render_timeout: timeout)
      end

      assert EGraph.num_tuples(graph) == {:ok, 0}

      assert {:error, {:invalid_option, _}} =
               EGraph.run(graph, "(relation added ())", render_timeout: 1)
    end)
  end

  @theory """
  (datatype Math (Num i64) (Add Math Math))
  (rewrite (Add a (Num 0)) a)
  (let x (Add (Num 1) (Num 0)))
  """

  test "a type error mentioning Check failed is still an error" do
    EGraph.with_egraph(fn graph ->
      assert {:error, {:native_error, _}} = EGraph.check(graph, ~s[(= "Check failed" 1)])
      assert {:ok, false} = EGraph.check(graph, "(= 1 2)")
      assert {:error, {:check_failed, _}} = EGraph.run(graph, "(check (= 1 2))")
    end)

    Program.with_program("", fn program ->
      assert {:error, {:native_error, _}} = Program.check(program, "", ~s[(= "Check failed" 1)])
      assert {:ok, false} = Program.check(program, "", "(= 1 2)")
    end)
  end

  test "cumulative statistics are outputs rather than additions to per-run totals" do
    Program.with_program(@theory, fn program ->
      assert {:ok, plain} = Program.run(program, "(run 2)")
      assert {:ok, printed} = Program.run(program, "(run 2)\n(print-stats)\n(print-stats)")
      assert plain.stats.matches > 0
      assert printed.stats.matches == plain.stats.matches
      assert printed.stats.iterations == plain.stats.iterations
      assert printed.report.matches_per_rule == plain.report.matches_per_rule
      assert Enum.count(printed.outputs, &(&1.type == :overall_statistics)) == 2
    end)
  end

  test "extraction selects its appended request and detects truncation" do
    Program.with_program(@theory, fn program ->
      assert {:ok, "(Num 2)"} = Program.extract(program, "(extract (Num 1))", "(Num 2)")

      assert {:error, {:missing_extraction, _}} =
               Program.extract(program, "(extract (Num 1))", "(Num 2)", output_limit: 1)

      assert {:error, {:missing_extraction, _}} =
               Program.extract(program, "(print-size)", "x", output_limit: 1)

      assert_raise RuntimeError, fn ->
        Program.extract!(program, "(print-size)", "x", output_limit: 1)
      end
    end)
  end

  test "request helpers normalize input keys before appending their request" do
    Program.with_program("", fn program ->
      input = %{"source" => "", "requests" => ["(extract 1)"]}

      assert {:ok, "3"} = Program.extract(program, input, "(+ 1 2)")
      assert {:ok, true} = Program.check(program, input, "(= 1 1)")
      assert :ok = Program.check_fail(program, input, "(= 1 2)")

      assert {:error, {:invalid_option, "duplicate option requests"}} =
               Program.extract(program, Map.put(input, :requests, []), "1")

      assert {:error, {:invalid_option, _}} =
               Program.check(program, %{requests: :invalid}, "(= 1 1)")
    end)
  end

  test "creator exits close graph servers whether normal or abnormal" do
    for reason <- [:normal, :shutdown] do
      parent = self()

      owner =
        spawn(fn ->
          {:ok, graph} = EGraph.new()
          send(parent, {:graph, graph})

          receive do
            :stop -> exit(reason)
          end
        end)

      assert_receive {:graph, graph}
      monitor = Process.monitor(graph.pid)
      send(owner, :stop)
      assert_receive {:DOWN, ^monitor, :process, _, :normal}, 2_000
      assert {:error, {:closed, _}} = EGraph.num_tuples(graph)
    end
  end

  test "other processes can use a handle while its creator lives" do
    EGraph.with_egraph(fn graph ->
      assert {:ok, 0} = Task.async(fn -> EGraph.num_tuples(graph) end) |> Task.await()
    end)
  end

  test "scoped helpers preserve callback results and clean up after exceptions and throws" do
    assert :answer == EGraph.with_egraph(fn _ -> :answer end)
    assert :answer == Program.with_program("", fn _ -> :answer end)
    parent = self()

    assert_raise RuntimeError, "callback failed", fn ->
      EGraph.with_egraph(fn graph ->
        send(parent, {:closed_graph, graph})
        raise "callback failed"
      end)
    end

    assert_receive {:closed_graph, graph}
    refute Process.alive?(graph.pid)

    assert :thrown ==
             catch_throw(
               Program.with_program("", fn program ->
                 send(parent, {:closed_program, program})
                 throw(:thrown)
               end)
             )

    assert_receive {:closed_program, program}
    assert {:error, {:closed, _}} = Program.num_tuples(program)
    assert {:error, {:invalid_theory, _}} = Program.with_program("(invalid", fn _ -> flunk() end)
  end

  test "invalid options cannot mutate native state" do
    EGraph.with_egraph(fn graph ->
      for opts <- [
            [snapshop: :json],
            [snapshot_max_functions: -1],
            [output_limit: 0],
            [snapshot_inline_leaves: "bad"],
            [snapshot_split_primitive_outputs: :yes],
            [snapshot_max_calls_per_function: 9_223_372_036_854_775_808],
            [{:snapshot, :json}, {"snapshot", :dot}]
          ] do
        assert {:error, {:invalid_option, _}} = EGraph.run(graph, "(relation touched ())", opts)
        assert {:ok, 0} = EGraph.num_tuples(graph)
      end

      assert {:error, {:invalid_option, _}} =
               EGraph.run(graph, %{source: "(relation touched ())"})

      assert {:error, {:invalid_option, _}} = EGraph.push(graph, -1)
      assert {:error, {:invalid_option, _}} = EGraph.lookup(graph, "x", [1])
      assert {:ok, _} = EGraph.run(graph, "(relation touched ())")
    end)
  end

  test "program inputs, budgets, requests, and parsed-run options are validated" do
    Program.with_program(@theory, fn program ->
      for input <- [
            %{budget: %{rounds: -1}},
            %{requests: [%{type: :extract}]},
            %{requests: [%{type: :extract, expr: "x", variants: -1}]},
            %{unrecognized: true},
            %{terms: %{x: "(Num 1)"}}
          ] do
        assert {:error, {:invalid_option, _}} = Program.run(program, input)
        assert {:error, {:invalid_option, _}} = Program.eval(program, input, "1")
      end

      assert {:error, {:invalid_option, _}} = Program.load("", default_budget: %{rounds: -1})
      assert {:error, {:invalid_option, _}} = Program.load(%{src: ""})
      assert {:error, {:invalid_option, _}} = EGraph.new("", proofs: :yes)
      commands = Commands.parse!("(extract x)")
      assert {:error, {:invalid_option, _}} = Program.run(program, commands, output_limit: -1)
      assert {:error, {:invalid_option, _}} = Program.extract(program, "", "x", variants: -1)
    end)
  end

  test "bang evaluation forwards scheduling options" do
    Program.with_program("(function answer () i64)\n(rule () ((set (answer) 42)))", fn program ->
      assert %{value: 42} = Program.eval!(program, "", "(answer)", budget: %{rounds: 1})
    end)
  end

  test "string option keys normalize before artifact and extraction helpers" do
    Program.with_program(@theory, fn program ->
      assert {:ok, snapshot} =
               Program.snapshot(program, "", %{
                 "render" => "json",
                 "snapshot_max_functions" => "2"
               })

      assert snapshot.format == :json
      assert {:ok, expected} = Program.extract(program, "", "(Num 1)", variants: 1)
      assert {:ok, ^expected} = Program.extract(program, "", "(Num 1)", %{"variants" => "1"})
    end)
  end

  @tag :tmp_dir
  test "non-bang snapshot writing returns errors, and bang writing raises", %{tmp_dir: dir} do
    blocked = Path.join(dir, "file")
    File.write!(blocked, "keep me")
    target = Path.join(blocked, "child.json")

    EGraph.with_egraph(fn graph ->
      assert {:error, {:snapshot_io, ^target, _}} =
               EGraph.snapshot(graph, render: :json, path: target)

      assert_raise RuntimeError, fn -> EGraph.snapshot!(graph, render: :json, path: target) end
      assert File.read!(blocked) == "keep me"
      assert {:ok, 0} = EGraph.num_tuples(graph)
    end)
  end

  test "native command errors preserve earlier changes without implicit rollback" do
    EGraph.with_egraph(fn graph ->
      assert {:error, {:check_failed, _}} =
               EGraph.run(graph, "(relation seen (i64))\n(seen 1)\n(check (= 1 2))")

      assert {:ok, true} = EGraph.check(graph, "(seen 1)")
      assert {:ok, 1} = EGraph.num_tuples(graph)
    end)
  end
end
