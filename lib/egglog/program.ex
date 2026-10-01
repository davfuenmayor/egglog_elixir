defmodule Egglog.Program do
  @moduledoc """
  Loaded egglog program used for query-local runs.

  A `Program` is a plain handle to a loaded native egglog base e-graph
  containing static declarations, rulesets, rules, and any persistent theory
  facts. Each `run/3` call clones that base inside native egglog and executes
  the supplied input as query-local work.

  Concurrent calls against one program are serialized by its native resource,
  including clone-local execution. Runs use dirty CPU schedulers; independent
  program handles can execute concurrently. Closing waits for an active call.
  No worker pool or global lock is introduced.

  `run/3` returns `{:ok, %{status: status, outputs: outputs, stats: stats,
  report: report}}`, optionally including a snapshot. Each output has `:type`
  and native `:text`. `:limit` means returned output was truncated, not that
  execution stopped. `eval/4` and `lookup/5` return values with `:sort`, `:type`
  and `:value`; primitive values are decoded, other native values remain text.
  Big integers and rationals retain their exact string representations.

  Invalid options return `{:error, {:invalid_option, message}}` before execution.
  Native errors retain their text. Failed checks use `:check_failed`; caught
  panics use `:panic`. A panic in a query-local clone does not mutate the base.
  """

  alias Egglog.{Commands, Common, Native, Options}

  @enforce_keys [:ref]
  defstruct [:ref, modes: %{}, default_budget: %{rounds: 0}, name: nil]

  @load_doc """
  Loads a static egglog program into a reusable native handle.

  The theory may be a raw egglog source string or a map containing `:source` or
  `:program`.

  Supported options:

    * `:name` - human-readable program name stored in the returned struct.
      Defaults to `nil`; it is not passed to native egglog.

    * `:proofs` - create the native e-graph with proof support enabled.
      Defaults to `false`. Truthy values are `true`, `"true"`, `"1"`, and `1`;
      False values are `false`, `"false"`, `"0"`, and `0`; other values return an error.

    * `:modes` - map from mode names to egglog schedule forms or commands.
      Defaults to `%{}`. During `run/3`, the selected `:mode` is looked up by
      the mode value and by `to_string(mode)`.

    * `:default_budget` - map merged into each non-parsed `run/3` input
      budget. Defaults to `%{}`. Currently `:rounds`/`"rounds"` and
      `:output_limit`/`"output_limit"` are read by `run/3`.

  String option keys are also accepted, matching the rest of the wrapper.
  """

  @run_doc """
  Runs query-local egglog code against the loaded program.

  The loaded base program is cloned inside native egglog for each run. The
  clone receives query-local input and the loaded base is not mutated.

  `input` may be:

    * a raw egglog source string,
    * a list of raw egglog command strings,
    * a parsed `%Egglog.Commands{}` handle returned by `parse/1`, or
    * a map with structured fields rendered to egglog source.

  Structured input map fields:

    * `:source` or `:program` - raw egglog source emitted first. Defaults to
      unset.
    * `:commands` - list of raw egglog commands emitted after source.
      Defaults to `[]`.
    * `:terms` - map rendered as `(let name expr)` commands. Defaults to `%{}`.
    * `:facts` - list of raw fact/command strings. Defaults to `[]`.
    * `:sets` - list of `{call, value}` tuples rendered as `(set call value)`.
      Defaults to `[]`.
    * `:unions` - list of `{left, right}` tuples rendered as
      `(union left right)`. Defaults to `[]`.
    * `:requests` - list of output-producing requests emitted last. Defaults
      to `[]`. Supported request maps are `:check`, `:extract`,
      `:print_size`, and `:print_function`; raw request strings are also
      accepted.
    * `:schedule` - egglog schedule string. Defaults to unset. Blank strings
      emit no schedule; strings starting with `(run` are emitted unchanged;
      other nonblank strings are wrapped as `(run-schedule schedule)`.
    * `:mode` - mode name used when no `:schedule` is supplied. Defaults to
      `:default`.
    * `:budget` - map merged after the program default budget and before the
      `opts[:budget]` map. Defaults to `%{}`.
    * snapshot fields listed below may also be supplied in the input map; opts
      take precedence over input map snapshot fields.

  Supported options:

    * `:mode` - selected mode when no input `:schedule` is supplied. Defaults
      to input `:mode`, then `:default`. The selected mode is looked up in the
      program's `:modes` map before `:budget` rounds are considered.

    * `:budget` - map merged after `program.default_budget` and input
      `:budget`. Defaults to `%{}`. Currently `:rounds`/`"rounds"` emits
      `(run rounds)` when positive and no selected mode schedule exists.
      `:output_limit`/`"output_limit"` is used as the default output limit for
      non-parsed inputs.

    * `:output_limit` - maximum number of native command outputs to keep in
      the returned `:outputs` list. Defaults to `budget[:output_limit]` for
      non-parsed inputs and unset for parsed command handles. Values must be
      positive integers; invalid values return an error. When outputs are
      truncated, the returned result has `status: :limit`.

    * `:snapshot` - request a native snapshot after the input has run.
      Defaults to input `:snapshot`, then `:none`.

      Accepted values:

      * `:none`, `"none"`, `false`, or `nil` - do not include a snapshot.
      * `:dot`, `"dot"`, or `true` - include native Graphviz DOT text.
      * `:json` or `"json"` - include native JSON snapshot text.

      `run/3` does not render DOT to SVG. Use `snapshot/3` when you want
      `render: :auto` or `render: :svg` post-processing.

    * `:snapshot_max_functions` - value passed to native egglog's
      `SerializeConfig.max_functions` when `:snapshot` is enabled. Defaults to
      input `:snapshot_max_functions`, then `0`. Values greater than `0` become
      `Some(value)`; `0` becomes `None`; invalid values return an error.

    * `:snapshot_max_calls_per_function` - value passed to native egglog's
      `SerializeConfig.max_calls_per_function` when `:snapshot` is enabled.
      Defaults to input `:snapshot_max_calls_per_function`, then `0`. Values
      greater than `0` become `Some(value)`; `0` becomes `None`; invalid values return an error.

    * `:snapshot_inline_leaves` - number of native leaf-inlining passes to use
      on the serialized snapshot before producing DOT or JSON text. Defaults
      to input `:snapshot_inline_leaves`, then `0`. Negative or invalid values
      return an error.

    * `:snapshot_split_primitive_outputs` - whether the native serialized
      snapshot should split primitive outputs into separate classes before
      producing DOT or JSON text. Defaults to input
      `:snapshot_split_primitive_outputs`, then `false`.

  For parsed `%Egglog.Commands{}` input, `:output_limit` and the snapshot
  options above are used. `:mode` is passed through to native result metadata,
  but no mode schedule is injected because the command sequence is already
  parsed. Structured input fields and budget-derived schedules are not rebuilt.

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

  @program_query_opts_doc """
  Supported options are the query-construction subset of `run/3` options:

    * `:mode` - selected mode when no input `:schedule` is supplied. Defaults
      to input `:mode`, then `:default`.
    * `:budget` - map merged after program default budget and input `:budget`.
      Defaults to `%{}`. Currently `:rounds`/`"rounds"` can emit a `(run n)`
      command when no selected mode schedule exists.

  `:output_limit` and snapshot options are not used by this function because it
  does not return command outputs or snapshots.

  String option keys are also accepted, matching the rest of the wrapper.
  """

  @program_check_doc """
  Runs a native egglog check and returns `{:ok, true}` or `{:ok, false}`.

  Supported options are the same as `run/3`; they are passed through to the
  internal run after appending `(check fact)` to the input requests. Defaults
  are therefore the `run/3` defaults.

  Only a failed egglog check is converted to `false`; parse/type/native errors
  are returned as `{:error, reason}`. Snapshot and output options may affect
  the internal run, but their result data is not exposed by this function.
  """

  @program_extract_doc """
  Extracts the cheapest native egglog term for `expr`.

  Supported options:

    * `:variants` - optional value inserted as the second argument to native
      egglog's `(extract expr variants)` command. Defaults to unset, which uses
      `(extract expr)`.

  All `run/3` options are also accepted and passed through after appending the
  extract request to the input. Defaults are the `run/3` defaults. Snapshot and
  output options may affect the internal run, but `extract/4` returns only the
  last extraction text. Missing or truncated extraction output returns an error.

  String option keys are also accepted, matching the rest of the wrapper.
  """

  @snapshot_doc """
  Builds a query-local e-graph snapshot.

  This is a convenience wrapper around `run/3`: it runs the query-local input
  against a native clone of the loaded program, requests a native DOT or JSON
  snapshot, then optionally renders or writes the serialized graph.

  Supported options:

    * `:render` - output format to return. Defaults to `:auto`.

      Accepted values:

      * `:auto`, `"auto"`, or `true` - render SVG with Graphviz when the
        `dot` executable is available on `PATH`; otherwise return DOT text.
      * `:svg` or `"svg"` - require Graphviz SVG rendering. Returns
        `{:error, {:graphviz_missing, message}}` if `dot` is unavailable.
      * `:dot`, `"dot"`, `false`, or `nil` - return Graphviz DOT text.
      * `:json` or `"json"` - return egglog's native JSON snapshot.

      Internally, `:render` determines the native `:snapshot` format passed to
      `run/3`: `:json` requests JSON; every other render value requests DOT.

    * `:mode` - selected mode when no input `:schedule` is supplied. Defaults
      to input `:mode`, then `:default`.

    * `:budget` - map merged after program default budget and input `:budget`.
      Defaults to `%{}`. Currently `:rounds`/`"rounds"` can emit a `(run n)`
      command when no selected mode schedule exists.

    * `:output_limit` - passed to the underlying `run/3`; it can truncate
      `snapshot.result.outputs`. Defaults to `budget[:output_limit]` for
      non-parsed inputs and unset for parsed command handles.

    * `:snapshot_max_functions` - value passed to native egglog's
      `SerializeConfig.max_functions`. Defaults to input
      `:snapshot_max_functions`, then `0`. Values greater than `0` become
      `Some(value)`; `0` becomes `None`; invalid values return an error.

    * `:snapshot_max_calls_per_function` - value passed to native egglog's
      `SerializeConfig.max_calls_per_function`. Defaults to input
      `:snapshot_max_calls_per_function`, then `0`. Values greater than `0`
      become `Some(value)`; `0` becomes `None`; invalid values return an error.

    * `:snapshot_inline_leaves` - number of native leaf-inlining passes to use
      on the serialized snapshot before producing DOT or JSON text. Defaults
      to input `:snapshot_inline_leaves`, then `0`. Negative or invalid values
      return an error.

    * `:snapshot_split_primitive_outputs` - whether the native serialized
      snapshot should split primitive outputs into separate classes before
      producing DOT or JSON text. Defaults to input
      `:snapshot_split_primitive_outputs`, then `false`.

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

  @doc """
  Parses egglog source into a reusable command handle.

  Parsed commands can be passed to `run/3`. This is useful when the same command
  sequence is executed repeatedly; native egglog parsing happens once, while
  execution still happens against a fresh clone of the loaded base program.
  """
  defdelegate parse(source), to: Commands

  @doc """
  Bang variant of `parse/1`.
  """
  defdelegate parse!(source), to: Commands

  @doc """
  Loads a program, returns `fun.(program)`, and closes it in `after`, including
  when the callback raises or throws. Load errors are returned unchanged.
  """
  def with_program(source, fun, opts \\ []) when is_function(fun, 1) do
    with {:ok, program} <- load(source, opts) do
      try do
        fun.(program)
      after
        close(program)
      end
    end
  end

  @doc @load_doc
  def load(theory_spec, opts \\ []) do
    Options.with_options(opts, :program_load, fn opts ->
      theory = if is_binary(theory_spec), do: %{source: theory_spec}, else: theory_spec

      with {:ok, theory} <- Options.validate(theory, [:source, :program]),
           {:ok, ref} <-
             Native.load_program(source_from(theory), Common.get(opts, :proofs, false))
             |> Common.from_native_load() do
        {:ok,
         %__MODULE__{
           ref: ref,
           modes: Common.get(opts, :modes, %{}),
           default_budget: Common.get(opts, :default_budget, %{}),
           name: Common.get(opts, :name)
         }}
      end
    end)
  end

  @doc """
  Bang variant of `load/2`.

  #{@load_doc}

  Raises if native egglog rejects the loaded theory.
  """
  def load!(theory_spec, opts \\ []) do
    theory_spec
    |> load(opts)
    |> Common.bang("failed to load egglog program")
  end

  @doc @run_doc
  def run(program, input, opts \\ [])

  def run(%__MODULE__{} = program, %Commands{} = commands, opts) do
    Options.with_options(opts, :program_run, fn opts ->
      mode = Common.get(opts, :mode, :default)
      snapshot = Common.snapshot_options(opts)

      program.ref
      |> Native.run_parsed_program(
        commands.ref,
        to_string(mode || :default),
        snapshot.format,
        snapshot.max_functions,
        snapshot.max_calls_per_function,
        snapshot.inline_leaves,
        snapshot.split_primitive_outputs?
      )
      |> Common.from_native_result(Common.get(opts, :output_limit))
    end)
  end

  def run(%__MODULE__{} = program, input, opts) do
    Options.with_options(opts, :program_run, fn opts ->
      with {:ok, input_map} <- Options.input(input) do
        budget = budget(program, input_map, opts)
        mode = mode(input_map, opts)
        source = build_run_source(program, input_map, budget, mode)

        output_limit = Common.get(opts, :output_limit, Common.get(budget, :output_limit))

        snapshot = Common.snapshot_options(opts, input_map)

        program.ref
        |> Native.run_program(
          source,
          to_string(mode || :default),
          snapshot.format,
          snapshot.max_functions,
          snapshot.max_calls_per_function,
          snapshot.inline_leaves,
          snapshot.split_primitive_outputs?
        )
        |> Common.from_native_result(output_limit)
      end
    end)
  end

  @doc """
  Bang variant of `run/3`.

  #{@run_doc}

  Raises if native egglog rejects the input or an option is invalid.
  """
  def run!(%__MODULE__{} = program, input, opts \\ []) do
    program
    |> run(input, opts)
    |> Common.bang("failed to run egglog program")
  end

  @doc @program_check_doc
  def check(%__MODULE__{} = program, input, fact, opts \\ []) when is_binary(fact) do
    program
    |> run_request(input, "(check #{fact})", opts)
    |> Common.check_result()
  end

  @doc """
  Boolean variant of `check/4`.

  #{@program_check_doc}

  It raises on non-check errors so syntax/type mistakes are not silently treated
  as false mathematical assertions.
  """
  def check?(%__MODULE__{} = program, input, fact, opts \\ []) do
    program
    |> check(input, fact, opts)
    |> Common.bang("failed to check egglog fact")
  end

  @doc """
  Asserts that a native egglog check fails.

  This maps to egglog's `(fail (check ...))` form and is useful for tests and
  tutorials that want to show a negative example without surfacing an exception.

  Supported options are the same as `run/3`; they are passed through to the
  internal run after appending `(fail (check fact))` to the input requests.
  Defaults are therefore the `run/3` defaults. Only `:ok` or `{:error, reason}`
  is returned.
  """
  def check_fail(%__MODULE__{} = program, input, fact, opts \\ []) when is_binary(fact) do
    program
    |> run_request(input, "(fail (check #{fact}))", opts)
    |> Common.ok_only()
  end

  @doc @program_extract_doc
  def extract(%__MODULE__{} = program, input, expr, opts \\ []) when is_binary(expr) do
    Options.with_options(opts, :program_extract, fn opts ->
      program
      |> run_request(
        input,
        Common.extract_request(expr, opts),
        Map.delete(opts, :variants)
      )
      |> Common.extraction()
    end)
  end

  @doc """
  Bang variant of `extract/4`.

  #{@program_extract_doc}

  Raises if native egglog rejects the input or extraction output is not
  available.
  """
  def extract!(%__MODULE__{} = program, input, expr, opts \\ []) do
    program
    |> extract(input, expr, opts)
    |> Common.bang("failed to extract egglog term")
  end

  @doc """
  Evaluates an egglog expression after applying query-local input.

  Primitive values are decoded into Elixir values. Non-primitive e-class values
  are returned with `type: :value`.

  #{@program_query_opts_doc}
  """
  def eval(%__MODULE__{} = program, input, expr, opts \\ []) when is_binary(expr) do
    Options.with_options(opts, :program_query, fn opts ->
      with {:ok, source} <- run_source(program, input, opts) do
        program.ref |> Native.eval_program(source, expr) |> Common.from_native_value()
      end
    end)
  end

  @doc """
  Bang variant of `eval/4`.

  Evaluates an egglog expression after applying query-local input.

  #{@program_query_opts_doc}

  Raises if native egglog rejects the query-local input or expression.
  """
  def eval!(%__MODULE__{} = program, input, expr, opts \\ []) do
    program
    |> eval(input, expr, opts)
    |> Common.bang("failed to evaluate egglog expression")
  end

  @doc """
  Looks up a function row after evaluating the given argument expressions.

  Returns `{:ok, nil}` when no row exists for the evaluated key.

  #{@program_query_opts_doc}
  """
  def lookup(%__MODULE__{} = program, input, name, arg_exprs, opts \\ [])
      when is_binary(name) and is_list(arg_exprs) do
    Options.with_options(opts, :program_query, fn opts ->
      with {:ok, source} <- run_source(program, input, opts),
           true <- Enum.all?(arg_exprs, &is_binary/1) do
        program.ref
        |> Native.lookup_program(source, name, arg_exprs)
        |> Common.from_native_lookup()
      else
        false -> {:error, {:invalid_option, "lookup arguments must be source strings"}}
        error -> error
      end
    end)
  end

  @doc """
  Bang variant of `lookup/5`.

  Looks up a function row after evaluating the given argument expressions.

  #{@program_query_opts_doc}

  Raises if native egglog rejects the query-local input or lookup expression.
  """
  def lookup!(%__MODULE__{} = program, input, name, arg_exprs, opts \\ []) do
    program
    |> lookup(input, name, arg_exprs, opts)
    |> Common.bang("failed to look up egglog function")
  end

  @doc @snapshot_doc
  def snapshot(%__MODULE__{} = program, input, opts \\ []) do
    Options.with_options(opts, :program_snapshot, fn opts ->
      {render, run_opts} = Common.snapshot_run_opts(opts)

      with {:ok, result} <- run(program, input, run_opts),
           {:ok, snapshot} <- Common.snapshot_from_result(result, opts, render) do
        {:ok, snapshot}
      end
    end)
  end

  @doc """
  Bang variant of `snapshot/3`.

  #{@snapshot_doc}

  Raises if native egglog rejects the input, Graphviz rendering fails, or
  artifact writing fails.
  """
  def snapshot!(%__MODULE__{} = program, input, opts \\ []) do
    program
    |> snapshot(input, opts)
    |> Common.bang("failed to snapshot egglog e-graph")
  end

  @doc """
  Returns native egglog's tuple count for the loaded base program.

  This wraps Rust egglog's `EGraph::num_tuples()` for the reusable base program.
  Query-local facts inserted by `run/3` do not mutate this base. For
  query-local node/class counts, visualization, or JSON inspection, use
  `snapshot/3` on the query you want to inspect.
  """
  def num_tuples(%__MODULE__{} = program) do
    program.ref |> Native.program_num_tuples() |> Common.from_native_count()
  end

  @doc """
  Closes the native loaded-program resource.
  """
  def close(%__MODULE__{} = program) do
    program.ref |> Native.close_program() |> Common.from_native_close()
  end

  defp build_run_source(program, input, budget, mode) do
    [
      Common.get(input, :source) || Common.get(input, :program),
      Common.get(input, :commands, []),
      raw_terms(Common.get(input, :terms, %{})),
      Common.get(input, :facts, []),
      raw_sets(Common.get(input, :sets, [])),
      raw_unions(Common.get(input, :unions, [])),
      schedule_command(program, input, budget, mode),
      raw_requests(Common.get(input, :requests, []))
    ]
    |> Common.join_commands()
  end

  defp run_source(program, input, opts) do
    with {:ok, input} <-
           Options.input(if(match?(%Commands{}, input), do: input.source || "", else: input)) do
      {:ok, build_run_source(program, input, budget(program, input, opts), mode(input, opts))}
    end
  end

  defp budget(program, input, opts) do
    program.default_budget
    |> Map.merge(normalize_map(Common.get(input, :budget, %{})))
    |> Map.merge(normalize_map(Common.get(opts, :budget, %{})))
  end

  defp mode(input, opts), do: Common.get(opts, :mode, Common.get(input, :mode, :default))

  defp run_request(program, %Commands{source: source}, request, opts),
    do: run_request(program, source || "", request, opts)

  defp run_request(program, input, request, opts) do
    with {:ok, input} <- Options.input(input) do
      run(program, Map.update(input, :requests, [request], &(&1 ++ [request])), opts)
    end
  end

  defp schedule_command(program, input, budget, mode) do
    case Common.get(input, :schedule) do
      nil -> mode_or_budget_schedule(program, budget, mode)
      schedule -> schedule_to_command(schedule)
    end
  end

  defp mode_or_budget_schedule(program, budget, mode) do
    mode_schedule = Map.get(program.modes, mode) || Map.get(program.modes, to_string(mode))

    rounds = Common.get(budget, :rounds, 0)

    cond do
      is_binary(mode_schedule) ->
        schedule_to_command(mode_schedule)

      rounds > 0 ->
        "(run #{rounds})"

      true ->
        nil
    end
  end

  defp schedule_to_command(schedule) when is_binary(schedule) do
    trimmed = String.trim(schedule)

    cond do
      Common.blank?(trimmed) -> nil
      String.starts_with?(trimmed, "(run") -> trimmed
      true -> "(run-schedule #{trimmed})"
    end
  end

  defp raw_terms(terms) when is_map(terms) do
    Enum.map(terms, fn {name, expr} -> "(let #{name} #{expr})" end)
  end

  defp raw_sets(sets) when is_list(sets) do
    Enum.map(sets, fn {call, value} -> "(set #{call} #{value})" end)
  end

  defp raw_unions(unions) when is_list(unions) do
    Enum.map(unions, fn {left, right} -> "(union #{left} #{right})" end)
  end

  defp raw_requests(requests) when is_list(requests), do: Enum.map(requests, &raw_request/1)

  defp raw_request(request) when is_binary(request), do: request

  defp raw_request(request) when is_map(request) do
    type = Common.get(request, :type)

    case normalize_type(type) do
      :check ->
        "(check #{Common.required!(request, :expr)})"

      :extract ->
        expr = Common.required!(request, :expr)

        case Common.get(request, :variants) || Common.get(request, :limit) do
          nil -> "(extract #{expr})"
          variants -> "(extract #{expr} #{variants})"
        end

      :print_size ->
        case Common.get(request, :name) do
          nil -> "(print-size)"
          name -> "(print-size #{name})"
        end

      :print_function ->
        name = Common.required!(request, :name)
        limit = Common.get(request, :limit, 20)
        "(print-function #{name} #{limit})"

      other ->
        raise ArgumentError, "unsupported egglog request type: #{inspect(other)}"
    end
  end

  defp source_from(source) when is_binary(source), do: source

  defp source_from(spec) when is_map(spec),
    do: Common.get(spec, :source) || Common.get(spec, :program) || ""

  defp normalize_map(nil), do: %{}
  defp normalize_map(map) when is_map(map), do: map
  defp normalize_map(list) when is_list(list), do: Map.new(list)

  defp normalize_type(type) when is_atom(type), do: type

  defp normalize_type(type) when is_binary(type) do
    case String.trim(type) do
      "check" -> :check
      "extract" -> :extract
      "print_size" -> :print_size
      "print-function" -> :print_function
      "print_function" -> :print_function
      other -> other
    end
  end
end
