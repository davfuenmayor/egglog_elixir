defmodule Egglog.NativeApiTest do
  use ExUnit.Case, async: true

  alias Egglog.{EGraph, Program}

  @source """
  (function score (i64) i64 :no-merge)
  (set (score 1) 42)
  (set (score 2) 43)
  (relation edge (i64 i64))
  (edge 1 2)
  (edge 2 3)
  """

  test "declarations expose native schemas and flags, including constructors" do
    EGraph.with_egraph(@source, fn graph ->
      assert {:ok, declarations} = EGraph.functions(graph)
      assert Enum.any?(declarations, &(&1.name == "score"))

      assert {:ok, %{input: ["i64"], output: "i64", subtype: :function, hidden: false}} =
               EGraph.function(graph, "score")

      assert {:ok, %{input: ["i64", "i64"], subtype: :constructor}} =
               EGraph.function(graph, "edge")

      assert {:ok, nil} = EGraph.function(graph, "absent")
    end)

    Program.with_program(@source, fn program ->
      assert %{name: "score"} = Program.function!(program, "score")
      assert Enum.any?(Program.functions!(program), &(&1.name == "edge"))
      assert {:ok, nil} = Program.function(program, "absent")
    end)
  end

  test "lookup delegates functions and constructors without inserting a missing row" do
    EGraph.with_egraph(@source, fn graph ->
      assert {:ok, %{value: 42}} = EGraph.lookup(graph, "score", ["1"])
      assert {:ok, %{type: :value}} = EGraph.lookup(graph, "edge", ["1", "2"])
      assert {:ok, nil} = EGraph.lookup(graph, "edge", ["7", "8"])
      assert {:ok, []} = EGraph.query(graph, [], ["(edge 7 8)"])
      assert {:error, {:native_error, _}} = EGraph.lookup(graph, "score", ["true"])
      assert {:error, {:native_error, _}} = EGraph.lookup(graph, "score", [])
    end)
  end

  test "native pattern queries return typed bindings and handle joins and ground facts" do
    EGraph.with_egraph(@source, fn graph ->
      assert {:ok, [%{"x" => %{sort: "i64", type: :integer, value: 1}, "z" => %{value: 3}}]} =
               EGraph.query(graph, [x: "i64", z: "i64"], ["(edge x y)", "(edge y z)"])

      assert [%{}] = EGraph.query!(graph, [], ["(edge 1 2)"])
      assert [] = EGraph.query!(graph, [], ["(edge 8 9)"])
      assert [%{"v" => %{value: 42}}] = EGraph.query!(graph, [v: "i64"], ["(= (score 1) v)"])
      assert {:error, {:native_error, _}} = EGraph.query(graph, [x: "unknown"], ["(edge x 2)"])
      assert {:error, {:native_error, _}} = EGraph.query(graph, [x: "String"], ["(edge x 2)"])
      assert {:error, {:native_error, _, _}} = EGraph.query(graph, [], ["(invalid"])
      assert {:error, {:invalid_option, _}} = EGraph.query(graph, [{:x, "i64"}, {"x", "i64"}], [])
      assert [%{}] = EGraph.query!(graph, [], ["(edge 1 2)"])
    end)
  end

  test "program queries apply input on a clone and leave the base unchanged" do
    Program.with_program(@source, fn program ->
      assert [%{}] = Program.query!(program, "(edge 3 4)", [], ["(edge 3 4)"])
      assert [] = Program.query!(program, "", [], ["(edge 3 4)"])
      assert [%{"x" => %{value: 2}}] = Egglog.query!(program, "", [{"x", "i64"}], ["(edge 1 x)"])

      assert {:error, {:invalid_option, _}} =
               Program.query(program, "", [], [], budget: %{rounds: -1})
    end)
  end

  test "upstream proof incompatibility is an error and leaves handles usable" do
    EGraph.with_egraph(
      @source,
      fn graph ->
        assert {:error, {:native_error, message}} = EGraph.query(graph, [], ["(edge 1 2)"])
        assert message =~ "proof"
        assert {:ok, true} = EGraph.check(graph, "(edge 1 2)")
      end,
      proofs: true
    )

    Program.with_program(
      @source,
      fn program ->
        assert {:error, {:native_error, _}} = Program.query(program, "", [], ["(edge 1 2)"])
        assert {:ok, true} = Program.check(program, "", "(edge 1 2)")
      end,
      proofs: true
    )
  end

  test "native table clearing preserves the declaration and respects rollback" do
    EGraph.with_egraph(@source, fn graph ->
      assert :ok = EGraph.push(graph)
      assert :ok = EGraph.clear_function(graph, "score")
      assert {:ok, nil} = EGraph.lookup(graph, "score", ["1"])
      assert %{name: "score"} = EGraph.function!(graph, "score")
      assert :ok = EGraph.pop(graph)
      assert {:ok, %{value: 42}} = EGraph.lookup(graph, "score", ["1"])
      assert :ok = EGraph.clear_function!(graph, "edge")
      assert [] = EGraph.query!(graph, [], ["(edge 1 2)"])
      assert {:error, {:native_error, _}} = EGraph.clear_function(graph, "absent")
      assert {:ok, %{value: 42}} = EGraph.lookup(graph, "score", ["1"])
    end)
  end

  test "native thread configuration belongs to each graph and is inherited by program clones" do
    EGraph.with_egraph(
      fn graph ->
        EGraph.with_egraph(fn other ->
          assert {:ok, 2} = EGraph.num_threads(graph)
          assert {:ok, 1} = EGraph.num_threads(other)
          assert :ok = EGraph.set_num_threads(graph, 1)
          assert {:ok, 1} = EGraph.num_threads(graph)
          assert {:error, {:invalid_option, _}} = EGraph.set_num_threads(graph, -1)
          assert {:ok, 1} = EGraph.num_threads(graph)
        end)
      end,
      num_threads: 2
    )

    Program.with_program(
      @source,
      fn program ->
        assert {:ok, 2} = Program.num_threads(program)
        assert [%{}] = Program.query!(program, "", [], ["(edge 1 2)"])
      end,
      %{"num_threads" => 2}
    )

    assert {:error, {:invalid_option, _}} = Program.load("", num_threads: -1)
    assert {:error, {:invalid_option, _}} = EGraph.new("", num_threads: :many)
  end

  test "unexpected server exits retain the diagnostic reason" do
    EGraph.with_egraph(fn graph ->
      :ok = :sys.suspend(graph.pid)
      task = Task.async(fn -> EGraph.num_tuples(graph) end)
      # The request is queued while suspended, so killing the server is observed
      # by an in-flight call rather than converted to a later :noproc result.
      wait_for_request(graph.pid)
      Process.exit(graph.pid, :kill)
      assert {:error, {:session_exit, :killed}} = Task.await(task)
      assert {:error, {:closed, _}} = EGraph.num_tuples(graph)
    end)
  end

  defp wait_for_request(pid, attempts \\ 1_000)
  defp wait_for_request(_pid, 0), do: flunk("server call was not queued")

  defp wait_for_request(pid, attempts) do
    receive do
    after
      1 ->
        case Process.info(pid, :message_queue_len) do
          {:message_queue_len, count} when count > 0 -> :ok
          _ -> wait_for_request(pid, attempts - 1)
        end
    end
  end
end
