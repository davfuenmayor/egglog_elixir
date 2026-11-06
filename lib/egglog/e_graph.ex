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

  The server monitors the creating process and closes when it exits, normally
  or abnormally. Other processes may call the shared handle while its creator
  lives. Calls use an infinite timeout because native runs cannot be cancelled
  by a GenServer timeout; finite waiting would not stop mutation or free the
  server for another request.

  Failed native commands can leave earlier changes in place; the wrapper does
  not add transactions. Use native `push/2` and `pop/2` for rollback points.
  A caught panic discards the mutable graph and stops the server. Further calls
  return `{:error, {:closed, message}}`. Unexpected server exits retain their
  reason as `{:error, {:session_exit, reason}}`. Validation errors occur before execution.
  Parser failures include structured source locations; see `Egglog` for the
  error shape and coordinate conventions.
  Run outputs and decoded values have the same shapes as `Egglog.Program`.

  `push/2` and `pop/2` delegate to native egglog's `(push)` and `(pop)`
  commands. They are useful for temporary experiments:

      :ok = Egglog.EGraph.push(eg)
      {:ok, _} = Egglog.EGraph.run(eg, "(let tmp (A))")
      :ok = Egglog.EGraph.pop(eg)

  The result shape of `run/3` matches `Egglog.Program.run/3`: outputs are a
  list of `%{type: atom(), text: String.t()}` maps and stats are a compact map.
  """

  alias Egglog.{Commands, Common, Options}
  alias Egglog.EGraph.Server

  @enforce_keys [:pid]
  defstruct [:pid, name: nil]

  @snapshot_doc """
  Builds a snapshot of the current mutable e-graph.

  This runs no new egglog commands; it asks native egglog to serialize the
  session's current state, then optionally renders or writes that serialized
  graph.

  Supported options:

    * `:render` - output format to return. Defaults to `:auto`.

      Accepted values:

      * `:auto`, `"auto"`, or `true` - render native DOT as SVG when Graphviz
        is available; otherwise convert native JSON to Mermaid. Discovery tries
        `EGGLOG_GRAPHVIZ_DOT`, then `GRAPHVIZ_DOT`, then `dot` on PATH. Environment
        values must name an executable, not a shell command; invalid values are
        ignored. If a detected renderer fails or times out, retain native DOT.
      * `:svg` or `"svg"` - require Graphviz SVG rendering. Returns
        `{:error, {:graphviz_missing, message}}` if `dot` is unavailable.
      * `:dot`, `"dot"`, `false`, or `nil` - return Graphviz DOT text.
      * `:json` or `"json"` - return egglog's native JSON snapshot.
      * `:mermaid` or `"mermaid"` - convert native JSON to Mermaid source without
        Graphviz. Pass `snapshot.mermaid` to `Kino.Mermaid.new/1`.


    * `:render_timeout` - positive Graphviz time limit in milliseconds; defaults
      to `30_000`. Expiration terminates the renderer and returns
      `{:error, {:graphviz_timeout, milliseconds}}` for explicit SVG requests;
      automatic rendering falls back to DOT text.
      Native execution and session state are unaffected. DOT/JSON output does
      not invoke Graphviz.

    * `:snapshot_max_functions` - value passed to native egglog's
      `SerializeConfig.max_functions`. Defaults to `0`. Values greater than
      `0` become `Some(value)`; `0` becomes `None`; invalid values return an error.

    * `:snapshot_max_calls_per_function` - value passed to native egglog's
      `SerializeConfig.max_calls_per_function`. Defaults to `0`. Values
      greater than `0` become `Some(value)`; `0` becomes `None`; invalid values return an error.

    * `:snapshot_inline_leaves` - number of native leaf-inlining passes to use
      on the serialized snapshot before producing DOT or JSON text. Defaults
      to `0`. Negative or invalid values return an error.

    * `:snapshot_split_primitive_outputs` - whether the native serialized
      snapshot should split primitive outputs into separate classes before
      producing DOT or JSON text. Defaults to `false`.

    * `:path` - optional file path where the returned `:text` payload is
      written. Defaults to unset.

    * `:dot_path` - optional file path where DOT is written when DOT text is
      available. Defaults to unset. For JSON/Mermaid renders, this key is recorded
      as `nil` if provided because no DOT text is produced.

    * `:svg_path` - optional file path where SVG is written when SVG rendering
      succeeds. Defaults to unset. For non-SVG renders, this key is recorded as
      `nil` if provided.

    * `:mermaid_path` - optional destination for Mermaid source (.mmd).
      It is nil on renders that do not produce Mermaid. Mermaid snapshots also
      retain native JSON, so json_path exports that same input.

    * `:json_path` - optional file path where JSON is written when
      JSON or Mermaid rendering is used. Defaults to unset. Otherwise, this
      key is recorded as `nil` if provided.

  The returned snapshot map contains:

    * `:format` - one of `:dot`, `:svg`, `:json`, or `:mermaid`.
    * `:text` - the primary payload for the selected render.
    * `:dot`, `:svg`, `:json`, or `:mermaid` - the format-specific payload when present.
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
      kept. Values must be positive integers; invalid values return an error. When
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
      to `0`. Negative or invalid values return an error.

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
  may affect the internal run, but `extract/3` returns only the last extraction text. Missing or truncated extraction output returns an error.

  String option keys are also accepted, matching the rest of the wrapper.
  """

  @doc """
  Parses egglog source into a reusable command handle.
  """
  defdelegate parse(source), to: Commands

  @doc """
  Bang variant of `parse/1`.
  """
  defdelegate parse!(source), to: Commands

  @doc """
  Creates a process-owned mutable native e-graph session.

  `source` is optional initial egglog code. Unlike `Egglog.Program`, this state
  is not a read-only base: later `run/3` calls mutate it directly through the
  session owner process.

  Options:

    * `:num_threads` - native worker threads for this graph. Defaults to `1`
      (serial); `0` uses available parallelism. Other graphs are unaffected.

    * `:name` - human-readable session name stored in the returned struct.
      Defaults to `nil`; it is not passed to native egglog.

    * `:proofs` - create the native e-graph with proof support enabled.
      Defaults to `false`. Truthy values are `true`, `"true"`, `"1"`, and `1`;
      False values are `false`, `"false"`, `"0"`, and `0`; other values return an error.

  String option keys are also accepted, matching the rest of the wrapper.
  """
  def new(source \\ "", opts \\ []) when is_binary(source) do
    Options.with_options(opts, :graph_load, fn opts ->
      proofs? = Common.get(opts, :proofs, false)

      with {:ok, pid} <-
             Server.start(
               source: source,
               proofs?: proofs?,
               num_threads: Common.get(opts, :num_threads, 1),
               owner: self()
             ) do
        {:ok, %__MODULE__{pid: pid, name: Common.get(opts, :name)}}
      end
    end)
  end

  @doc """
  Creates a graph, returns `fun.(graph)`, and closes it in `after`, including
  when the callback raises or throws. Creation errors are returned unchanged.
  """
  def with_egraph(fun) when is_function(fun, 1), do: with_egraph("", fun, [])

  @doc "Runs a scoped callback with creation options, or with initial source and default options."
  def with_egraph(fun, opts) when is_function(fun, 1), do: with_egraph("", fun, opts)

  def with_egraph(source, fun) when is_binary(source) and is_function(fun, 1),
    do: with_egraph(source, fun, [])

  @doc "Loads initial source, runs a scoped callback, and closes the graph even on callback failure."
  def with_egraph(source, fun, opts) when is_binary(source) and is_function(fun, 1) do
    with {:ok, graph} <- new(source, opts) do
      try do
        fun.(graph)
      after
        close(graph)
      end
    end
  end

  @doc @run_doc
  def run(egraph, input, opts \\ [])

  def run(%__MODULE__{} = egraph, %Commands{} = commands, opts) do
    Options.with_options(opts, :graph_run, fn opts ->
      snapshot = Common.snapshot_options(opts)

      Server.call(
        egraph.pid,
        {:run_parsed, commands.ref, snapshot, Common.get(opts, :output_limit)}
      )
    end)
  end

  def run(%__MODULE__{pid: pid}, input, opts) do
    Options.with_options(opts, :graph_run, fn opts ->
      with {:ok, %{source: source}} <- graph_input(input) do
        program = source
        snapshot = Common.snapshot_options(opts)
        Server.call(pid, {:run, program, snapshot, Common.get(opts, :output_limit)})
      end
    end)
  end

  @doc """
  Bang variant of `run/3`.

  #{@run_doc}

  Raises if native egglog rejects the input or an option is invalid.
  """
  def run!(%__MODULE__{} = egraph, input, opts \\ []) do
    egraph
    |> run(input, opts)
    |> Common.bang("failed to run egglog program")
  end

  @doc @check_doc
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
  def check_fail(%__MODULE__{} = egraph, fact, opts \\ []) when is_binary(fact) do
    egraph
    |> run("(fail (check #{fact}))", opts)
    |> Common.ok_only()
  end

  @doc @extract_doc
  def extract(%__MODULE__{} = egraph, expr, opts \\ []) when is_binary(expr) do
    Options.with_options(opts, :graph_extract, fn opts ->
      egraph
      |> run(Common.extract_request(expr, opts), Map.delete(opts, :variants))
      |> Common.extraction()
    end)
  end

  @doc """
  Bang variant of `extract/3`.

  #{@extract_doc}

  Raises if native egglog rejects the input or extraction output is not
  available.
  """
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
  def eval(%__MODULE__{pid: pid}, expr) when is_binary(expr) do
    Server.call(pid, {:eval, expr})
  end

  @doc """
  Bang variant of `eval/2`.
  """
  def eval!(%__MODULE__{} = egraph, expr) do
    egraph
    |> eval(expr)
    |> Common.bang("failed to evaluate egglog expression")
  end

  @doc """
  Looks up a function or constructor row after evaluating its argument expressions.

  Returns `{:ok, nil}` when no row exists for the evaluated key.
  """
  def lookup(%__MODULE__{pid: pid}, name, arg_exprs)
      when is_binary(name) and is_list(arg_exprs) do
    if Enum.all?(arg_exprs, &is_binary/1),
      do: Server.call(pid, {:lookup, name, arg_exprs}),
      else: {:error, {:invalid_option, "lookup arguments must be source strings"}}
  end

  @doc """
  Bang variant of `lookup/3`.
  """
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
  def push(%__MODULE__{} = egraph, count \\ 1) do
    with {:ok, %{count: count}} <- Options.validate([count: count], [:count]) do
      egraph |> run(stack_command("push", count)) |> Common.ok_only()
    end
  end

  @doc """
  Pops native egglog rollback points.

  `count` defaults to `1`. Popping too much returns an error from native egglog.
  """
  def pop(%__MODULE__{} = egraph, count \\ 1) do
    with {:ok, %{count: count}} <- Options.validate([count: count], [:count]) do
      egraph |> run(stack_command("pop", count)) |> Common.ok_only()
    end
  end

  @doc @snapshot_doc
  def snapshot(%__MODULE__{} = egraph, opts \\ []) do
    Options.with_options(opts, :graph_snapshot, fn opts ->
      {render, run_opts} = Common.snapshot_run_opts(opts)

      with {:ok, result} <- run(egraph, "", run_opts),
           {:ok, snapshot} <- Common.snapshot_from_result(result, opts, render) do
        {:ok, snapshot}
      end
    end)
  end

  @doc """
  Bang variant of `snapshot/2`.

  #{@snapshot_doc}

  Raises if snapshot serialization, Graphviz rendering, or artifact writing
  fails.
  """
  def snapshot!(%__MODULE__{} = egraph, opts \\ []) do
    egraph
    |> snapshot(opts)
    |> Common.bang("failed to snapshot egglog e-graph")
  end

  @doc """
  Lists all native function and constructor declarations in registration order.

  Each map contains `:name`, input sort names in `:input`, the `:output` sort,
  `:subtype` (`:function` or `:constructor`), and native `:hidden`, `:let_binding`
  and `:can_subsume` flags. Hidden compiler declarations are included.
  """
  def functions(%__MODULE__{pid: pid}), do: Server.call(pid, :functions)

  @doc "Bang variant of `functions/1`."
  def functions!(graph), do: functions(graph) |> Common.bang("failed to inspect egglog functions")

  @doc "Returns the native declaration map described by `functions/1`, or `{:ok, nil}` for an unknown name."
  def function(%__MODULE__{pid: pid}, name) when is_binary(name),
    do: Server.call(pid, {:function, name})

  @doc "Bang variant of `function/2`; an unknown name returns `nil`."
  def function!(graph, name),
    do: function(graph, name) |> Common.bang("failed to inspect egglog function")

  @doc """
  Removes all rows of a native table, preserving its declaration. Returns `:ok`.

  Delegates to upstream `clear_function`; it accepts function and constructor
  names. An unknown name returns a native error. This mutates the graph and
  follows native `push`/`pop` rollback behavior.
  """
  def clear_function(%__MODULE__{pid: pid}, name) when is_binary(name),
    do: Server.call(pid, {:clear_function, name})

  @doc "Bang variant of `clear_function/2`."
  def clear_function!(graph, name) do
    case clear_function(graph, name) do
      :ok -> :ok
      {:error, reason} -> raise "failed to clear egglog function: #{inspect(reason)}"
    end
  end

  @doc """
  Runs upstream's native pattern query and returns `{:ok, binding_maps}`.

  `vars` names each requested variable and its sort, e.g. `[x: "i64"]` or
  `[{"x", "i64"}]`; `facts` is a list of native fact strings such as `["(R x)"]`.
  Each match maps string variable names to the same typed value maps as `eval/2`.
  Row order is unspecified. No matches returns `[]`; a matching ground query
  with no variables returns `[%{}]`.

  This delegates parsing, typechecking and matching to Rust. Upstream currently
  rejects pattern queries with proofs enabled; that native error is returned.
  The native query adds and removes its temporary rule; it does not run your
  persistent rules or undo earlier graph mutations.
  """
  def query(%__MODULE__{pid: pid}, vars, facts) do
    with {:ok, vars, facts} <- Common.query_inputs(vars, facts),
         do: Server.call(pid, {:query, vars, facts})
  end

  @doc "Bang variant of `query/3`."
  def query!(graph, vars, facts),
    do: query(graph, vars, facts) |> Common.bang("failed to query egglog")

  @doc "Returns `{:ok, count}` for this graph's native worker-thread configuration."
  def num_threads(%__MODULE__{pid: pid}), do: Server.call(pid, :num_threads)

  @doc """
  Changes this graph's native thread count. `1` runs serially; `0` chooses
  available parallelism. Returns `:ok`. Other graphs are unaffected.
  """
  def set_num_threads(%__MODULE__{pid: pid}, count) do
    Options.with_options([num_threads: count], :thread_settings, fn opts ->
      Server.call(pid, {:set_num_threads, opts.num_threads})
    end)
  end

  @doc """
  Returns native egglog's tuple count for the current mutable session.

  This wraps Rust egglog's `EGraph::num_tuples()`. It is a coarse
  database-size counter, not a graph summary. For node/class counts,
  visualization, or JSON inspection, use `snapshot/2`.
  """
  def num_tuples(%__MODULE__{pid: pid}) do
    Server.call(pid, :num_tuples)
  end

  @doc """
  Closes the native mutable e-graph and stops the session process.
  """
  def close(%__MODULE__{pid: pid}) do
    monitor = Process.monitor(pid)
    result = Server.call(pid, :close)

    receive do
      {:DOWN, ^monitor, :process, ^pid, _reason} -> result
    end
  end

  defp graph_input(input) when is_binary(input), do: {:ok, %{source: input}}

  defp graph_input(input) when is_list(input) do
    with {:ok, %{commands: commands}} <- Options.input(input) do
      {:ok, %{source: Common.join_commands(commands)}}
    end
  end

  defp graph_input(_), do: {:error, {:invalid_option, "graph input must be source or commands"}}

  defp stack_command(name, 1), do: "(#{name})"
  defp stack_command(name, count), do: "(#{name} #{count})"
end
