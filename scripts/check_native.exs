# Run with mix run, or elixir -pa PATH/ebin for each relocated runtime dependency.
{:ok, _} = Application.ensure_all_started(:egglog_elixir)
alias Egglog.{EGraph, Program, Snapshot}

theory = """
(datatype Math (Num i64) (Add Math Math))
(relation edge (i64 i64))
(edge 1 2)
(edge 2 3)
(relation big (i64))
(big 9223372036854775807)
(let x (Add (Num 1) (Num 0)))
"""

EGraph.with_egraph(
  theory,
  fn graph ->
    {:ok, commands} = EGraph.parse("(rewrite (Add a (Num 0)) a) (run 3)")
    {:ok, _} = EGraph.run(graph, commands)
    "(Num 1)" = EGraph.extract!(graph, "x")

    [%{"left" => %{value: 1}, "right" => %{value: 3}}] =
      EGraph.query!(graph, [left: "i64", right: "i64"], [
        "(edge left middle)",
        "(edge middle right)"
      ])

    [%{"n" => %{value: 9_223_372_036_854_775_807}}] =
      EGraph.query!(graph, [n: "i64"], ["(big n)"])

    :ok = EGraph.push(graph)
    {:ok, _} = EGraph.run(graph, "(edge 3 4)")
    true = EGraph.check?(graph, "(edge 3 4)")
    :ok = EGraph.pop(graph)
    false = EGraph.check?(graph, "(edge 3 4)")
    %{format: :json} = json = EGraph.snapshot!(graph, render: :json)
    true = Snapshot.summary(json).nodes > 0
    %{format: :dot} = EGraph.snapshot!(graph, render: :dot)
  end,
  num_threads: 2
)

Program.with_program(theory, fn program ->
  [%{}] = Program.query!(program, "(edge 3 4)", [], ["(edge 3 4)"])
  [] = Program.query!(program, "", [], ["(edge 3 4)"])
end)

IO.puts(
  "PASS native queries, extraction, parsed commands, rollback, int64, snapshots and isolation"
)

IO.inspect({:os.type(), :erlang.system_info(:system_architecture)}, label: "Runtime")
