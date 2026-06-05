defmodule Egglog.EGraph do
  @moduledoc """
  Process-owned mutable native egglog e-graph session.

  `Egglog.EGraph` is the interactive counterpart to `Egglog.Program`.
  Use it when you want egglog state to persist across calls, as in a REPL,
  Livebook, or exploratory workflow:

      {:ok, eg} = Egglog.EGraph.new()
      {:ok, _} = Egglog.EGraph.run(eg, "(datatype T (A) (B))")
      {:ok, _} = Egglog.EGraph.run(eg, "(let x (A))")

  Each successful `run/3` mutates the native e-graph owned by this session's
  Elixir process. Concurrent callers are serialized through that owner process.
  This is intentionally different from `Egglog.Program.run/3`, which runs each
  query against a native clone of a loaded base program.

  `push/2` and `pop/2` delegate to native egglog's `(push)` and `(pop)`
  commands. They are useful for temporary experiments:

      :ok = Egglog.EGraph.push(eg)
      {:ok, _} = Egglog.EGraph.run(eg, "(let tmp (A))")
      :ok = Egglog.EGraph.pop(eg)

  The result shape of `run/3` matches `Egglog.Program.run/3`: outputs are a
  list of `%{type: atom(), text: String.t()}` maps and stats are a compact map.
  """

  alias Egglog.{Commands, Common}
  alias Egglog.EGraph.Server

  @enforce_keys [:pid]
  defstruct [:pid, name: nil]

  @opaque t :: %__MODULE__{pid: pid(), name: String.t() | nil}

  @snapshot_doc """
  Builds a snapshot of the current mutable e-graph.

  This runs no new egglog commands; it asks native egglog to serialize the
  session's current state, then optionally renders or writes that serialized
  graph.

  Supported options:

    * `:render` - output format to return. Defaults to `:auto`.

      Accepted values:

      * `:auto`, `"auto"`, or `true` - render SVG with Graphviz when the
        `dot` executable is available on `PATH`; otherwise return DOT text.
      * `:svg` or `"svg"` - require Graphviz SVG rendering. Returns
        `{:error, {:graphviz_missing, message}}` if `dot` is unavailable.
      * `:dot`, `"dot"`, `false`, or `nil` - return Graphviz DOT text.
      * `:json` or `"json"` - return egglog's native JSON snapshot.

    * `:snapshot_max_functions` - value passed to native egglog's
      `SerializeConfig.max_functions`. Defaults to `0`. Values greater than
      `0` become `Some(value)`; `0` and invalid values become `None`.

    * `:snapshot_max_calls_per_function` - value passed to native egglog's
      `SerializeConfig.max_calls_per_function`. Defaults to `0`. Values
      greater than `0` become `Some(value)`; `0` and invalid values become
      `None`.

    * `:snapshot_inline_leaves` - number of native leaf-inlining passes to use
      on the serialized snapshot before producing DOT or JSON text. Defaults
      to `0`. Negative or invalid values behave like `0`.

    * `:snapshot_split_primitive_outputs` - whether the native serialized
      snapshot should split primitive outputs into separate classes before
      producing DOT or JSON text. Defaults to `false`.

    * `:path` - optional file path where the returned `:text` payload is
      written. Defaults to unset.

    * `:dot_path` - optional file path where DOT is written when DOT text is
      available. Defaults to unset. For `render: :json`, this key is recorded
      as `nil` if provided because no DOT text is produced.

    * `:svg_path` - optional file path where SVG is written when SVG rendering
      succeeds. Defaults to unset. For non-SVG renders, this key is recorded as
      `nil` if provided.

    * `:json_path` - optional file path where JSON is written when
      `render: :json` is used. Defaults to unset. For non-JSON renders, this
      key is recorded as `nil` if provided.

  The returned snapshot map contains:

    * `:format` - one of `:dot`, `:svg`, or `:json`.
    * `:text` - the primary payload for the selected render.
    * `:dot`, `:svg`, or `:json` - the format-specific payload when present.
    * `:omitted` - native omission metadata for capped snapshots.
    * `:stats` - snapshot-specific native stats, currently
      `:snapshot_nodes` and `:snapshot_classes` when available.
    * `:result` - the underlying `run/3` result used to obtain the native
      serialization.
    * any provided artifact path keys after successful writes.

  String option keys are also accepted, matching the rest of the wrapper.
  """

  @run_doc """
  Runs egglog code against the mutable session.

  On success, native egglog state is retained for future calls. On error,
  egglog may have applied commands that appeared before the failing command in
  the same program; use `push/2` and `pop/2` around speculative work when you
  need an explicit rollback point.

  `input` may be:

    * a raw egglog source string,
    * a list of raw egglog command strings, or
    * a parsed `%Egglog.Commands{}` handle returned by `parse/1`.

  Supported options:

    * `:output_limit` - maximum number of native command outputs to keep in
      the returned `:outputs` list. Defaults to unset, meaning all outputs are
      kept. Values must be positive integers; invalid values are ignored. When
      outputs are truncated, the returned result has `status: :limit`.

    * `:snapshot` - request a native snapshot after the input has run.
      Defaults to `:none`.

      Accepted values:

      * `:none`, `"none"`, `false`, or `nil` - do not include a snapshot.
      * `:dot`, `"dot"`, or `true` - include native Graphviz DOT text.
      * `:json` or `"json"` - include native JSON snapshot text.

      `run/3` does not render DOT to SVG. Use `snapshot/2` when you want
      `render: :auto` or `render: :svg` post-processing.

    * `:snapshot_max_functions` - value passed to native egglog's
      `SerializeConfig.max_functions` when `:snapshot` is enabled. Defaults to
      `0`. Values greater than `0` become `Some(value)`; `0` and invalid
      values become `None`.

    * `:snapshot_max_calls_per_function` - value passed to native egglog's
      `SerializeConfig.max_calls_per_function` when `:snapshot` is enabled.
      Defaults to `0`. Values greater than `0` become `Some(value)`; `0` and
      invalid values become `None`.

    * `:snapshot_inline_leaves` - number of native leaf-inlining passes to use
      on the serialized snapshot before producing DOT or JSON text. Defaults
      to `0`. Negative or invalid values behave like `0`.

    * `:snapshot_split_primitive_outputs` - whether the native serialized
      snapshot should split primitive outputs into separate classes before
      producing DOT or JSON text. Defaults to `false`.

  The returned result map contains:

    * `:status` - native run status, or `:limit` when `:output_limit`
      truncated outputs.
    * `:outputs` - list of `%{type: atom(), text: String.t()}` command
      outputs.
    * `:stats` - compact numeric/text stats from native egglog.
    * `:report` - per-rule/per-ruleset reporting data from native egglog.
    * `:snapshot` - present only when `:snapshot` is `:dot` or `:json`;
      contains `%{format: :dot | :json, text: binary(), omitted: term()}`.

  String option keys are also accepted, matching the rest of the wrapper.
  """

  @check_doc """
  Runs a native egglog check against the current mutable session.

  Supported options are the same as `run/3`; they are passed through to the
  internal `(check ...)` run. Defaults are therefore the `run/3` defaults.

  Only the check result is returned. Snapshot and output options may affect the
  internal run, but their result data is not exposed by this function.
  """

  @extract_doc """
  Extracts the cheapest native egglog term for `expr` in the current session.

  Supported options:

    * `:variants` - optional value inserted as the second argument to native
      egglog's `(extract expr variants)` command. Defaults to unset, which uses
      `(extract expr)`.

  All `run/3` options are also accepted and passed through to the internal
  extract run. Defaults are the `run/3` defaults. Snapshot and output options
  may affect the internal run, but `extract/3` returns only the extracted text.

  String option keys are also accepted, matching the rest of the wrapper.
  """

  @typedoc """
  Raw or parsed egglog commands accepted by `run/3`.
  """
  @type input :: String.t() | [String.t()] | Commands.t()

  @typedoc """
  Decoded value returned by `eval/2` and `lookup/3`.

  `:value` contains a native egglog e-class value rendered as text. Primitive
  egglog values are decoded to ordinary Elixir values when possible:
  integers, floats, booleans, strings, and `nil` for unit.
  """
  @type value :: %{
          required(:sort) => String.t(),
          required(:type) => atom(),
          required(:value) => term()
        }

  @typedoc """
  Result returned by `run/3`.
  """
  @type run_result :: %{
          required(:status) => atom(),
          required(:outputs) => [%{required(:type) => atom(), required(:text) => String.t()}],
          required(:stats) => map(),
          required(:report) => map(),
          optional(:snapshot) => map()
        }

  @doc """
  Parses egglog source into a reusable command handle.
  """
  @spec parse(String.t()) :: {:ok, Commands.t()} | {:error, term()}
  defdelegate parse(source), to: Commands

  @doc """
  Bang variant of `parse/1`.
  """
  @spec parse!(String.t()) :: Commands.t()
  defdelegate parse!(source), to: Commands

  @doc """
  Creates a process-owned mutable native e-graph session.

  `source` is optional initial egglog code. Unlike `Egglog.Program`, this state
  is not a read-only base: later `run/3` calls mutate it directly through the
  session owner process.

  Options:

    * `:name` - human-readable session name stored in the returned struct.
      Defaults to `nil`; it is not passed to native egglog.

    * `:proofs` - create the native e-graph with proof support enabled.
      Defaults to `false`. Truthy values are `true`, `"true"`, `"1"`, and `1`;
      all other values are treated as false.

  String option keys are also accepted, matching the rest of the wrapper.
  """
  @spec new(String.t(), keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(source \\ "", opts \\ []) when is_binary(source) do
    opts = Common.option_map(opts)
    proofs? = Common.truthy?(Common.get(opts, :proofs, false))

    with {:ok, pid} <- Server.start(source: source, proofs?: proofs?) do
      Process.link(pid)
      {:ok, %__MODULE__{pid: pid, name: Common.get(opts, :name)}}
    end
  end

  @doc @run_doc
  @spec run(t(), input(), keyword() | map()) :: {:ok, run_result()} | {:error, term()}
  def run(egraph, input, opts \\ [])

  def run(%__MODULE__{} = egraph, %Commands{} = commands, opts) do
    opts = Common.option_map(opts)
    snapshot = Common.snapshot_options(opts)

    Server.call(
      egraph.pid,
      {:run_parsed, commands.ref, snapshot, Common.get(opts, :output_limit)}
    )
  end

  def run(%__MODULE__{pid: pid}, input, opts) do
    opts = Common.option_map(opts)
    program = normalize_input(input)
    snapshot = Common.snapshot_options(opts)

    Server.call(pid, {:run, program, snapshot, Common.get(opts, :output_limit)})
  end

  @doc """
  Bang variant of `run/3`.

  #{@run_doc}

  Raises if native egglog rejects the input or any option validation raises.
  """
  @spec run!(t(), input(), keyword() | map()) :: run_result()
  def run!(%__MODULE__{} = egraph, input, opts \\ []) do
    egraph
    |> run(input, opts)
    |> Common.bang("failed to run egglog program")
  end

  @doc @check_doc
  @spec check(t(), String.t(), keyword() | map()) :: {:ok, boolean()} | {:error, term()}
  def check(%__MODULE__{} = egraph, fact, opts \\ []) when is_binary(fact) do
    egraph
    |> run("(check #{fact})", opts)
    |> Common.check_result()
  end

  @doc """
  Boolean variant of `check/3`.

  #{@check_doc}

  Raises on non-check errors so syntax/type/native errors are not silently
  treated as false mathematical assertions.
  """
  @spec check?(t(), String.t(), keyword() | map()) :: boolean()
  def check?(%__MODULE__{} = egraph, fact, opts \\ []) do
    egraph
    |> check(fact, opts)
    |> Common.bang("failed to check egglog fact")
  end

  @doc """
  Asserts that a native egglog check fails.

  Supported options are the same as `run/3`; they are passed through to the
  internal `(fail (check ...))` run. Defaults are therefore the `run/3`
  defaults. Only `:ok` or `{:error, reason}` is returned.
  """
  @spec check_fail(t(), String.t(), keyword() | map()) :: :ok | {:error, term()}
  def check_fail(%__MODULE__{} = egraph, fact, opts \\ []) when is_binary(fact) do
    egraph
    |> run("(fail (check #{fact}))", opts)
    |> Common.ok_only()
  end

  @doc @extract_doc
  @spec extract(t(), String.t(), keyword() | map()) :: {:ok, String.t()} | {:error, term()}
  def extract(%__MODULE__{} = egraph, expr, opts \\ []) when is_binary(expr) do
    egraph
    |> run(Common.extract_request(expr, opts), opts)
    |> Common.extraction()
  end

  @doc """
  Bang variant of `extract/3`.

  #{@extract_doc}

  Raises if native egglog rejects the input or extraction output is not
  available.
  """
  @spec extract!(t(), String.t(), keyword() | map()) :: String.t()
  def extract!(%__MODULE__{} = egraph, expr, opts \\ []) do
    egraph
    |> extract(expr, opts)
    |> Common.bang("failed to extract egglog term")
  end

  @doc """
  Evaluates an egglog expression in the current mutable session.

  Primitive values are decoded into Elixir values. Non-primitive e-class values
  are returned with `type: :value`.
  """
  @spec eval(t(), String.t()) :: {:ok, value()} | {:error, term()}
  def eval(%__MODULE__{pid: pid}, expr) when is_binary(expr) do
    Server.call(pid, {:eval, expr})
  end

  @doc """
  Bang variant of `eval/2`.
  """
  @spec eval!(t(), String.t()) :: value()
  def eval!(%__MODULE__{} = egraph, expr) do
    egraph
    |> eval(expr)
    |> Common.bang("failed to evaluate egglog expression")
  end

  @doc """
  Looks up a function row after evaluating the given argument expressions.

  Returns `{:ok, nil}` when no row exists for the evaluated key.
  """
  @spec lookup(t(), String.t(), [String.t()]) :: {:ok, value() | nil} | {:error, term()}
  def lookup(%__MODULE__{pid: pid}, name, arg_exprs)
      when is_binary(name) and is_list(arg_exprs) do
    Server.call(pid, {:lookup, name, arg_exprs})
  end

  @doc """
  Bang variant of `lookup/3`.
  """
  @spec lookup!(t(), String.t(), [String.t()]) :: value() | nil
  def lookup!(%__MODULE__{} = egraph, name, arg_exprs) do
    egraph
    |> lookup(name, arg_exprs)
    |> Common.bang("failed to look up egglog function")
  end

  @doc """
  Pushes a native egglog rollback point.

  `count` defaults to `1`. This corresponds to `(push)` for `1`, or
  `(push count)` for larger counts.
  """
  @spec push(t(), pos_integer()) :: :ok | {:error, term()}
  def push(%__MODULE__{} = egraph, count \\ 1) do
    stack_command("push", count)
    |> then(&run(egraph, &1))
    |> Common.ok_only()
  end

  @doc """
  Pops native egglog rollback points.

  `count` defaults to `1`. Popping too much returns an error from native egglog.
  """
  @spec pop(t(), pos_integer()) :: :ok | {:error, term()}
  def pop(%__MODULE__{} = egraph, count \\ 1) do
    stack_command("pop", count)
    |> then(&run(egraph, &1))
    |> Common.ok_only()
  end

  @doc @snapshot_doc
  @spec snapshot(t(), keyword() | map()) :: {:ok, map()} | {:error, term()}
  def snapshot(%__MODULE__{} = egraph, opts \\ []) do
    opts = Common.option_map(opts)
    {render, run_opts} = Common.snapshot_run_opts(opts)

    with {:ok, result} <- run(egraph, "", run_opts),
         {:ok, snapshot} <- Common.snapshot_from_result(result, opts, render) do
      {:ok, snapshot}
    end
  end

  @doc """
  Bang variant of `snapshot/2`.

  #{@snapshot_doc}

  Raises if snapshot serialization, Graphviz rendering, or artifact writing
  fails.
  """
  @spec snapshot!(t(), keyword() | map()) :: map()
  def snapshot!(%__MODULE__{} = egraph, opts \\ []) do
    egraph
    |> snapshot(opts)
    |> Common.bang("failed to snapshot egglog e-graph")
  end

  @doc """
  Returns native egglog's tuple count for the current mutable session.

  This wraps Rust egglog's `EGraph::num_tuples()`. It is a coarse
  database-size counter, not a graph summary. For node/class counts,
  visualization, or JSON inspection, use `snapshot/2`.
  """
  @spec num_tuples(t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def num_tuples(%__MODULE__{pid: pid}) do
    Server.call(pid, :num_tuples)
  end

  @doc """
  Closes the native mutable e-graph and stops the session process.
  """
  @spec close(t()) :: :ok | {:error, term()}
  def close(%__MODULE__{pid: pid} = egraph) do
    result = Server.call(pid, :close)
    stop(egraph)
    result
  end

  defp stop(%__MODULE__{pid: pid}) do
    if Process.alive?(pid) do
      GenServer.stop(pid, :normal, :infinity)
    end
  catch
    :exit, _reason -> :ok
  end

  defp stack_command(_name, count) when not is_integer(count) or count < 1 do
    raise ArgumentError, "push/pop count must be a positive integer"
  end

  defp stack_command(name, 1), do: "(#{name})"
  defp stack_command(name, count), do: "(#{name} #{count})"

  defp normalize_input(input) when is_binary(input), do: input

  defp normalize_input(commands) when is_list(commands), do: Common.join_commands(commands)
end
