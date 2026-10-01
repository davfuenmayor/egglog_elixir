defmodule Egglog.EGraph.Server do
  @moduledoc false

  use GenServer

  alias Egglog.{Common, Native}

  def start(opts) do
    GenServer.start(__MODULE__, opts)
  end

  def call(pid, request) when is_pid(pid) do
    GenServer.call(pid, request, :infinity)
  catch
    :exit, {reason, {GenServer, :call, _}} when reason in [:noproc, :normal, :shutdown] ->
      {:error, {:closed, "egraph session is not available"}}

    :exit, {reason, {GenServer, :call, _}} ->
      {:error, {:session_exit, reason}}
  end

  @impl true
  def init(opts) do
    source = Keyword.fetch!(opts, :source)
    proofs? = Keyword.fetch!(opts, :proofs?)

    case Native.new_egraph(source, proofs?, Keyword.fetch!(opts, :num_threads))
         |> Common.from_native_load() do
      {:ok, ref} -> {:ok, %{ref: ref, owner: Process.monitor(Keyword.fetch!(opts, :owner))}}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(_request, _from, %{ref: nil} = state) do
    {:reply, {:error, {:closed, "egraph session is closed"}}, state}
  end

  def handle_call({:run, source, snapshot, output_limit}, _from, %{ref: ref} = state) do
    result =
      ref
      |> Native.run_egraph(
        source,
        snapshot.format,
        snapshot.max_functions,
        snapshot.max_calls_per_function,
        snapshot.inline_leaves,
        snapshot.split_primitive_outputs?
      )
      |> Common.from_native_result(output_limit)

    reply(result, state)
  end

  def handle_call({:run_parsed, commands_ref, snapshot, output_limit}, _from, %{ref: ref} = state) do
    result =
      ref
      |> Native.run_parsed_egraph(
        commands_ref,
        snapshot.format,
        snapshot.max_functions,
        snapshot.max_calls_per_function,
        snapshot.inline_leaves,
        snapshot.split_primitive_outputs?
      )
      |> Common.from_native_result(output_limit)

    reply(result, state)
  end

  def handle_call({:eval, expr}, _from, %{ref: ref} = state) do
    result =
      ref
      |> Native.eval_egraph(expr)
      |> Common.from_native_value()

    reply(result, state)
  end

  def handle_call({:lookup, name, arg_exprs}, _from, %{ref: ref} = state) do
    result =
      ref
      |> Native.lookup_egraph(name, arg_exprs)
      |> Common.from_native_lookup()

    reply(result, state)
  end

  def handle_call(:num_tuples, _from, %{ref: ref} = state) do
    result = ref |> Native.egraph_num_tuples() |> Common.from_native_count()
    reply(result, state)
  end

  def handle_call(:functions, _from, %{ref: ref} = state) do
    reply(Native.functions_egraph(ref) |> Common.from_native_functions(), state)
  end

  def handle_call({:function, name}, _from, %{ref: ref} = state) do
    reply(Native.function_egraph(ref, name) |> Common.from_native_function(), state)
  end

  def handle_call({:clear_function, name}, _from, %{ref: ref} = state) do
    reply(Native.clear_function_egraph(ref, name) |> Common.from_native_close(), state)
  end

  def handle_call({:query, vars, facts}, _from, %{ref: ref} = state) do
    reply(Native.query_egraph(ref, vars, facts) |> Common.from_native_bindings(), state)
  end

  def handle_call(:num_threads, _from, %{ref: ref} = state) do
    reply(Native.egraph_num_threads(ref) |> Common.from_native_count(), state)
  end

  def handle_call({:set_num_threads, count}, _from, %{ref: ref} = state) do
    reply(Native.set_egraph_num_threads(ref, count) |> Common.from_native_close(), state)
  end

  def handle_call(:close, _from, %{ref: ref} = state) do
    result = ref |> Native.close_egraph() |> Common.from_native_close()
    {:stop, :normal, result, %{state | ref: nil}}
  end

  @impl true
  def handle_info({:DOWN, monitor, :process, _pid, _reason}, %{owner: monitor} = state),
    do: {:stop, :normal, state}

  @impl true
  def terminate(_reason, %{ref: ref}) when not is_nil(ref), do: Native.close_egraph(ref)
  def terminate(_reason, _state), do: :ok

  defp reply({:error, {:panic, _}} = error, state),
    do: {:stop, :normal, error, state}

  defp reply(result, state), do: {:reply, result, state}
end
