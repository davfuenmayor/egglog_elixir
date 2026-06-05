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
    :exit, _reason -> {:error, {:closed, "egraph session is not available"}}
  end

  @impl true
  def init(opts) do
    source = Keyword.fetch!(opts, :source)
    proofs? = Keyword.fetch!(opts, :proofs?)

    case Native.new_egraph(source, proofs?) |> Common.from_native_load() do
      {:ok, ref} -> {:ok, %{ref: ref}}
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

    {:reply, result, state}
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

    {:reply, result, state}
  end

  def handle_call({:eval, expr}, _from, %{ref: ref} = state) do
    result =
      ref
      |> Native.eval_egraph(expr)
      |> Common.from_native_value()

    {:reply, result, state}
  end

  def handle_call({:lookup, name, arg_exprs}, _from, %{ref: ref} = state) do
    result =
      ref
      |> Native.lookup_egraph(name, arg_exprs)
      |> Common.from_native_lookup()

    {:reply, result, state}
  end

  def handle_call(:num_tuples, _from, %{ref: ref} = state) do
    result = ref |> Native.egraph_num_tuples() |> Common.from_native_count()
    {:reply, result, state}
  end

  def handle_call(:close, _from, %{ref: ref} = state) do
    result = ref |> Native.close_egraph() |> Common.from_native_close()
    {:reply, result, %{state | ref: nil}}
  end
end
