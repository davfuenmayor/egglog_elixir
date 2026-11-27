defmodule Egglog.InspectionTest do
  use ExUnit.Case, async: true

  alias Egglog.{Commands, EGraph, Program, Snapshot}

  @theory """
  (datatype E (N i64))
  (relation seen (i64))
  (function score (i64) String :no-merge)
  (seen 1)
  (seen 2)
  (set (score 1) "first")
  (N 3)
  """

  test "row inspection preserves native types and stops at the limit" do
    EGraph.with_egraph(@theory, fn graph ->
      before = EGraph.num_tuples(graph)

      assert %{truncated: true, rows: [%{output: %{sort: "@seenSort", type: :value}}]} =
               EGraph.rows!(graph, "seen", limit: 1)

      assert %{truncated: false, rows: [_, _]} = EGraph.rows!(graph, "seen", limit: 2)

      assert %{rows: [%{inputs: [%{value: 1}], output: %{value: "first"}, subsumed: false}]} =
               EGraph.rows!(graph, "score")

      assert %{rows: [%{inputs: [%{value: 3}], output: %{sort: "E", type: :value}}]} =
               EGraph.rows!(graph, "N")

      assert EGraph.num_tuples(graph) == before
      assert {:error, {:invalid_option, _}} = EGraph.rows(graph, "seen", limit: 0)
    end)

    Program.with_program(@theory, fn program ->
      assert %{rows: [_, _, _]} = Program.rows!(program, "(seen 3)", "seen")
      assert %{rows: [_, _]} = Program.rows!(program, "", "seen")
    end)
  end

  test "diagnostics preserve request stage, names and source spans without changing defaults" do
    source = "(run missing 1)"
    commands = Commands.parse!(source)

    EGraph.with_egraph("", fn graph ->
      assert {:error, {:native_error, _}} = EGraph.run(graph, commands)
    end)

    Program.with_program(
      "",
      fn program ->
        for input <- [source, commands] do
          assert {:error, {:native_error, _, details}} = Program.run(program, input)
          assert details.category == "ruleset_error"
          assert details.stage == "run"
          assert details.source == source
          assert details.names["ruleset"] == ["missing"]
          assert [%{source: ^source, location: %{start_line: 1}}] = details.locations
        end

        assert {:error, {:native_error, _, %{stage: "input", source: ^source}}} =
                 Program.eval(program, source, "1")

        assert {:ok, false} = Program.check(program, "", "(= 1 2)")
      end,
      error_details: true
    )
  end

  @tag :tmp_dir
  test "retained views can be rendered after close and export errors report completed writes",
       %{tmp_dir: dir} do
    snapshot =
      EGraph.with_egraph(@theory, fn graph ->
        EGraph.snapshot!(graph, render: :dot, snapshot_max_calls_per_function: 1)
      end)

    mermaid = Snapshot.render!(snapshot, render: :mermaid)
    assert mermaid.dot == snapshot.dot
    assert mermaid.json == snapshot.json
    assert mermaid.mermaid =~ "flowchart"
    refute mermaid.complete
    assert "seen" in mermaid.truncated_functions

    dot = Path.join(dir, "graph.dot")
    svg = Path.join(dir, "graph.svg")
    File.write!(dot, "old content")

    assert {:error, {:snapshot_io, ^svg, details}} =
             Snapshot.render(snapshot, render: :json, dot_path: dot, svg_path: svg)

    assert details.reason == {:format_unavailable, :svg_path}
    assert details.artifacts == %{dot_path: dot}
    assert File.read!(dot) == snapshot.dot
    refute File.exists?(svg)
    assert Enum.sort(File.ls!(dir)) == ["graph.dot"]
  end
end
