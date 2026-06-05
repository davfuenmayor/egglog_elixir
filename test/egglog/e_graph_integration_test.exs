defmodule Egglog.EGraphIntegrationTest do
  use ExUnit.Case, async: true

  alias Egglog.EGraph

  test "mutable sessions keep native state across run calls" do
    assert {:ok, egraph} =
             EGraph.new("""
             (datatype Math (Num i64) (Add Math Math))
             """)

    assert {:ok, first} = EGraph.run(egraph, "(let x (Add (Num 1) (Num 0)))")
    assert first.outputs == []

    assert {:ok, _} = EGraph.run(egraph, "(rewrite (Add a (Num 0)) a)")

    assert {:ok, result} =
             EGraph.run(egraph, """
             (run 2)
             (check (= x (Num 1)))
             (extract x)
             """)

    assert result.stats.matches > 0
    assert output_text(result, :extract) == "(Num 1)\n"
  end

  test "mutable sessions run parsed commands against retained state" do
    assert {:ok, egraph} =
             EGraph.new("""
             (datatype Math (Num i64) (Add Math Math))
             (let x (Add (Num 1) (Num 0)))
             """)

    assert {:ok, commands} =
             EGraph.parse("""
             (rewrite (Add a (Num 0)) a)
             (run 2)
             (extract x)
             """)

    assert commands.count == 3
    assert {:ok, result} = EGraph.run(egraph, commands)
    assert output_text(result, :extract) == "(Num 1)\n"
  end

  test "mutable check and extract helpers use current native state" do
    assert {:ok, egraph} =
             EGraph.new("""
             (datatype Math (Num i64) (Add Math Math))
             (let x (Add (Num 1) (Num 0)))
             (rewrite (Add a (Num 0)) a)
             """)

    assert {:ok, _} = EGraph.run(egraph, "(run 2)")
    assert {:ok, true} = EGraph.check(egraph, "(= x (Num 1))")
    assert EGraph.check?(egraph, "(= x (Num 1))")
    assert {:ok, false} = EGraph.check(egraph, "(= x (Num 2))")
    assert :ok = EGraph.check_fail(egraph, "(= x (Num 2))")
    assert {:ok, "(Num 1)"} = EGraph.extract(egraph, "x")
  end

  test "mutable eval helper inspects current native state" do
    assert {:ok, egraph} =
             EGraph.new("""
             (datatype Math (Num i64) (Add Math Math))
             (let x (Add (Num 1) (Num 0)))
             (rewrite (Add a (Num 0)) a)
             """)

    assert {:ok, %{sort: "i64", type: :integer, value: 7}} =
             EGraph.eval(egraph, "(+ 3 4)")

    assert {:ok, _} = EGraph.run(egraph, "(run 2)")

    assert {:ok, %{sort: "Math", type: :value, value: value}} =
             EGraph.eval(egraph, "x")

    assert is_binary(value)
  end

  test "mutable lookup helper uses retained rows and evaluated keys" do
    assert {:ok, egraph} =
             EGraph.new("""
             (function score (i64) i64 :merge (max old new))
             """)

    assert {:ok, nil} = EGraph.lookup(egraph, "score", ["1"])
    assert {:ok, _} = EGraph.run(egraph, "(set (score (+ 0 1)) 10)")

    assert {:ok, %{sort: "i64", type: :integer, value: 10}} =
             EGraph.lookup(egraph, "score", ["1"])
  end

  test "mutable sessions serialize concurrent callers through one owner process" do
    assert {:ok, egraph} =
             EGraph.new("""
             (function score (i64) i64 :merge (max old new))
             """)

    results =
      1..8
      |> Task.async_stream(
        fn n ->
          EGraph.run(egraph, "(set (score #{n}) #{n * 10})")
        end,
        max_concurrency: 4,
        timeout: 10_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.all?(results, &match?({:ok, _result}, &1))

    for n <- 1..8 do
      assert {:ok, %{sort: "i64", type: :integer, value: value}} =
               EGraph.lookup(egraph, "score", [to_string(n)])

      assert value == n * 10
    end
  end

  test "push and pop use native rollback points" do
    assert {:ok, egraph} =
             EGraph.new("""
             (datatype Term (A) (B))
             (let x (A))
             """)

    assert :ok = EGraph.push(egraph)
    assert {:ok, _} = EGraph.run(egraph, "(let y (B))")
    assert {:ok, _} = EGraph.run(egraph, "(check (= y (B)))")

    assert :ok = EGraph.pop(egraph)
    assert {:ok, _} = EGraph.run(egraph, "(check (= x (A)))")
    assert {:error, {:native_error, message}} = EGraph.run(egraph, "(check (= y (B)))")
    assert message =~ "Check failed"
  end

  test "pop reports native errors when the stack is empty" do
    assert {:ok, egraph} = EGraph.new()
    assert {:error, {:native_error, message}} = EGraph.pop(egraph)
    assert message =~ "Tried to pop too much"
  end

  test "mutable sessions can snapshot current state as json" do
    assert {:ok, egraph} =
             EGraph.new("""
             (datatype Expr (Num i64) (Add Expr Expr))
             """)

    assert {:ok, _} = EGraph.run(egraph, "(let x (Add (Num 1) (Num 2)))")

    assert {:ok, snapshot} =
             EGraph.snapshot(egraph,
               render: :json,
               snapshot_max_functions: 20,
               snapshot_max_calls_per_function: 20
             )

    assert snapshot.format == :json
    assert snapshot.stats.snapshot_nodes > 0
    assert snapshot.json =~ ~s("nodes")
    assert snapshot.json =~ "Add"
  end

  test "closed mutable sessions reject later operations" do
    assert {:ok, egraph} = EGraph.new("(datatype T (A))")
    assert :ok = EGraph.close(egraph)
    assert {:error, {:closed, _message}} = EGraph.run(egraph, "(let x (A))")
    assert {:error, {:closed, _message}} = EGraph.num_tuples(egraph)
    assert {:error, {:closed, _message}} = EGraph.eval(egraph, "(A)")
    assert {:error, {:closed, _message}} = EGraph.lookup(egraph, "f", [])
  end

  defp output_text(result, type) do
    result.outputs
    |> Enum.filter(&(&1.type == type))
    |> Enum.map_join(& &1.text)
  end
end
