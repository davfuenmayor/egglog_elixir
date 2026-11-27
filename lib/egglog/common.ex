defmodule Egglog.Common do
  @moduledoc false

  @snapshot_artifact_keys [:path, :dot_path, :svg_path, :json_path, :mermaid_path]
  @snapshot_render_keys [:render, :render_timeout]

  def errors({:error, reason, message, details}, true),
    do:
      {:error,
       {reason, message,
        %{details | names: Enum.group_by(details.names, &elem(&1, 0), &elem(&1, 1))}}}

  def errors({:error, reason, message, _details}, false), do: {:error, reason, message}
  def errors(result, _details), do: result

  def from_native_load({:ok, ref}), do: {:ok, ref}
  def from_native_load({:error, _reason} = error), do: error
  def from_native_load({:error, reason, message}), do: {:error, {reason, message}}

  def from_native_result({:error, _reason} = error, _limit), do: error

  def from_native_result({:error, reason, message}, _limit), do: {:error, {reason, message}}

  def from_native_result(
        {:ok, status, outputs, numeric_stats, text_stats, snapshot, report},
        limit
      ) do
    {outputs, limited?} = limit_outputs(outputs, limit)
    {snapshot_format, snapshot_omitted, snapshot_stats, data} = snapshot

    result = %{
      status: if(limited?, do: :limit, else: status),
      outputs:
        Enum.map(outputs, fn {type, text} -> %{type: String.to_atom(type), text: text} end),
      stats: stats(numeric_stats ++ snapshot_stats, text_stats),
      report: report(report)
    }

    {:ok, put_snapshot(result, snapshot_format, snapshot_omitted, data)}
  end

  def from_native_close(:ok), do: :ok
  def from_native_close({:error, _reason} = error), do: error
  def from_native_close({:error, reason, message}), do: {:error, {reason, message}}

  def from_native_value({:ok, sort, kind, value}), do: {:ok, value(sort, kind, value)}
  def from_native_value({:error, _reason} = error), do: error
  def from_native_value({:error, reason, message}), do: {:error, {reason, message}}

  def from_native_lookup({:ok, false, _sort, _kind, _value}), do: {:ok, nil}
  def from_native_lookup({:ok, true, sort, kind, value}), do: {:ok, value(sort, kind, value)}
  def from_native_lookup({:error, _reason} = error), do: error
  def from_native_lookup({:error, reason, message}), do: {:error, {reason, message}}

  def from_native_extraction({:ok, data}), do: {:ok, data}
  def from_native_extraction({:error, _reason} = error), do: error
  def from_native_extraction({:error, reason, message}), do: {:error, {reason, message}}

  def from_native_count({:ok, count}), do: {:ok, count}
  def from_native_count({:error, _reason} = error), do: error
  def from_native_count({:error, reason, message}), do: {:error, {reason, message}}

  def from_native_functions({:ok, functions}), do: {:ok, Enum.map(functions, &function/1)}
  def from_native_functions({:error, _reason} = error), do: error
  def from_native_functions({:error, reason, message}), do: {:error, {reason, message}}
  def from_native_function({:ok, nil}), do: {:ok, nil}
  def from_native_function({:ok, function}), do: {:ok, function(function)}
  def from_native_function({:error, _reason} = error), do: error
  def from_native_function({:error, reason, message}), do: {:error, {reason, message}}

  def from_native_rows({:ok, rows, truncated}) do
    {:ok,
     %{
       rows:
         Enum.map(rows, fn {inputs, output, subsumed} ->
           %{
             inputs: Enum.map(inputs, fn {sort, kind, raw} -> value(sort, kind, raw) end),
             output: then(output, fn {sort, kind, raw} -> value(sort, kind, raw) end),
             subsumed: subsumed
           }
         end),
       truncated: truncated
     }}
  end

  def from_native_rows({:error, _} = error), do: error
  def from_native_rows({:error, reason, message}), do: {:error, {reason, message}}

  def from_native_bindings({:ok, rows}) do
    {:ok,
     Enum.map(rows, fn row ->
       Map.new(row, fn {name, {sort, kind, raw}} -> {name, value(sort, kind, raw)} end)
     end)}
  end

  def from_native_bindings({:error, _reason} = error), do: error
  def from_native_bindings({:error, reason, message}), do: {:error, {reason, message}}

  def query_inputs(vars, facts) when is_list(vars) and is_list(facts) do
    valid_vars? =
      Enum.all?(vars, fn
        {name, sort} -> (is_atom(name) or is_binary(name)) and is_binary(sort)
        _ -> false
      end)

    if valid_vars? and Enum.all?(facts, &is_binary/1) do
      vars = Enum.map(vars, fn {name, sort} -> {to_string(name), sort} end)

      if length(Enum.uniq_by(vars, &elem(&1, 0))) == length(vars),
        do: {:ok, vars, facts},
        else: {:error, {:invalid_option, "duplicate query variable"}}
    else
      {:error,
       {:invalid_option,
        "query variables must be name/sort pairs and facts must be source strings"}}
    end
  end

  def query_inputs(_, _),
    do: {:error, {:invalid_option, "query variables and facts must be lists"}}

  defp function({name, input, output, subtype, hidden, let_binding, can_subsume}) do
    %{
      name: name,
      input: input,
      output: output,
      subtype: if(subtype == "function", do: :function, else: :constructor),
      hidden: hidden,
      let_binding: let_binding,
      can_subsume: can_subsume
    }
  end

  def snapshot_from_result(%{snapshot: native_snapshot, stats: stats} = result, opts, render) do
    with {:ok, rendered} <-
           render_snapshot(
             native_snapshot,
             render,
             get(opts, :render_timeout, 30_000)
           ) do
      snapshot =
        %{
          format: rendered.format,
          text: rendered.text,
          dot: native_snapshot.dot,
          svg: Map.get(rendered, :svg),
          json: native_snapshot.json,
          mermaid: Map.get(rendered, :mermaid),
          omitted: native_snapshot.omitted,
          complete: native_snapshot.complete,
          truncated_functions: native_snapshot.truncated_functions,
          discarded_functions: native_snapshot.discarded_functions,
          rendering: rendered.rendering,
          stats: Map.take(stats, [:snapshot_nodes, :snapshot_classes]),
          result: result
        }

      write_snapshot_artifacts(snapshot, opts)
    end
  end

  def snapshot_from_result(_result, _opts, _render), do: {:error, :missing_snapshot}

  def snapshot_options(opts, input \\ %{}) do
    %{
      format: get(opts, :snapshot, get(input, :snapshot, :none)) |> snapshot_format(),
      max_functions: get(opts, :snapshot_max_functions, get(input, :snapshot_max_functions, 0)),
      max_calls_per_function:
        get(
          opts,
          :snapshot_max_calls_per_function,
          get(input, :snapshot_max_calls_per_function, 0)
        ),
      inline_leaves: get(opts, :snapshot_inline_leaves, get(input, :snapshot_inline_leaves, 0)),
      split_primitive_outputs?:
        get(
          opts,
          :snapshot_split_primitive_outputs,
          get(input, :snapshot_split_primitive_outputs, false)
        )
    }
  end

  def native_snapshot_format(render) when render in [:json, "json", :mermaid, "mermaid"],
    do: :json

  def native_snapshot_format(render) when render in [:auto, "auto", true],
    do: if(Egglog.Graphviz.executable(), do: :dot, else: :json)

  def native_snapshot_format(_render), do: :dot

  def snapshot_run_opts(opts) do
    render = get(opts, :render, :auto)

    run_opts =
      opts
      |> Map.drop(@snapshot_artifact_keys ++ @snapshot_render_keys)
      |> Map.put(:snapshot, native_snapshot_format(render))

    {render, run_opts}
  end

  def check_result({:ok, _result}), do: {:ok, true}

  def check_result({:error, {:check_failed, _message, _details}}), do: {:ok, false}

  def check_result({:error, {:check_failed, _message}}), do: {:ok, false}

  def check_result({:error, reason}), do: {:error, reason}

  def ok_only({:ok, _result}), do: :ok
  def ok_only({:error, reason}), do: {:error, reason}

  def extract_request(expr, opts) do
    case get(opts, :variants) do
      nil -> "(extract #{expr})"
      variants -> "(extract #{expr} #{variants})"
    end
  end

  def extraction({:ok, %{status: :limit}}),
    do: {:error, {:missing_extraction, "requested extraction was truncated"}}

  def extraction({:ok, result}) do
    case Enum.find(Enum.reverse(result.outputs), &(&1.type in [:extract, :extract_variants])) do
      nil -> {:error, {:missing_extraction, "no extraction output"}}
      output -> {:ok, String.trim_trailing(output.text, "\n")}
    end
  end

  def extraction({:error, reason}), do: {:error, reason}

  def bang({:error, {:snapshot_io, path, %{reason: reason}}}, message),
    do: raise("#{message}: cannot export #{path}: #{inspect(reason)}")

  def bang({:ok, value}, _message), do: value
  def bang({:error, reason}, message), do: raise("#{message}: #{inspect(reason)}")

  def join_commands(commands) when is_list(commands) do
    commands
    |> List.flatten()
    |> Enum.reject(&blank?/1)
    |> Enum.join("\n")
  end

  def get(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end

  def required!(map, key),
    do: get(map, key) || raise(ArgumentError, "missing required key #{inspect(key)}")

  def blank?(nil), do: true
  def blank?(value) when is_binary(value), do: String.trim(value) == ""
  def blank?(_value), do: false

  defp stats(numeric_stats, text_stats) do
    numeric_stats
    |> Map.new(fn {key, value} -> {String.to_atom(key), value} end)
    |> Map.merge(Map.new(text_stats, fn {key, value} -> {String.to_atom(key), value} end))
  end

  defp report(report_groups) do
    Map.new(report_groups, fn {group, entries} ->
      {String.to_atom(group), Map.new(entries)}
    end)
  end

  defp value(sort, kind, raw) do
    %{
      sort: sort,
      type: String.to_atom(kind),
      value: decode_value(kind, raw)
    }
  end

  defp decode_value("integer", raw), do: String.to_integer(raw)

  defp decode_value("float", raw) do
    case Float.parse(raw) do
      {float, ""} -> float
      _other -> raw
    end
  end

  defp decode_value("boolean", "true"), do: true
  defp decode_value("boolean", "false"), do: false
  defp decode_value("unit", _raw), do: nil
  defp decode_value(_kind, raw), do: raw

  defp limit_outputs(outputs, nil), do: {outputs, false}

  defp limit_outputs(outputs, limit), do: {Enum.take(outputs, limit), length(outputs) > limit}

  defp put_snapshot(result, "", _omitted, _data), do: result
  defp put_snapshot(result, "none", _omitted, _data), do: result

  defp put_snapshot(result, format, omitted, data) do
    format = String.to_existing_atom(format)
    text = Map.fetch!(data, format)

    Map.put(
      result,
      :snapshot,
      Map.merge(data, %{format: format, text: text, omitted: omitted})
    )
  end

  defp render_snapshot(native, render, timeout) do
    executable = Egglog.Graphviz.executable()
    automatic? = render in [:auto, "auto", true]

    selected =
      cond do
        automatic? -> if(executable, do: :svg, else: :mermaid)
        render in [false, nil] -> :dot
        is_binary(render) -> String.to_existing_atom(render)
        true -> render
      end

    result =
      case selected do
        :dot ->
          {:ok, %{format: :dot, text: native.dot}}

        :json ->
          {:ok, %{format: :json, text: native.json}}

        :mermaid ->
          with {:ok, source} <- Egglog.Snapshot.to_mermaid(native.json),
               do: {:ok, %{format: :mermaid, text: source, mermaid: source}}

        :svg when is_nil(executable) ->
          {:error,
           {:graphviz_missing,
            "could not find Graphviz dot (EGGLOG_GRAPHVIZ_DOT, GRAPHVIZ_DOT or PATH)"}}

        :svg ->
          render_svg(native.dot, timeout, executable)
      end

    report = %{requested: render, executable: if(selected == :svg, do: executable), fallback: nil}

    case result do
      {:error, reason} when automatic? ->
        {:ok, %{format: :dot, text: native.dot, rendering: %{report | fallback: reason}}}

      {:ok, rendered} ->
        fallback = if automatic? and is_nil(executable), do: :graphviz_missing
        {:ok, Map.put(rendered, :rendering, %{report | fallback: fallback})}

      error ->
        error
    end
  end

  defp render_svg(dot, timeout, executable) do
    # A private directory avoids collisions across concurrent BEAM instances.
    directory =
      Path.join(
        System.tmp_dir!(),
        "egglog-#{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}"
      )

    dot_path = Path.join(directory, "graph.dot")
    svg_path = Path.join(directory, "graph.svg")

    try do
      with :ok <- File.mkdir(directory),
           :ok <- File.write(dot_path, dot),
           :ok <- if(match?({:unix, _}, :os.type()), do: File.chmod(directory, 0o700), else: :ok),
           {:ok, _} <- Egglog.Graphviz.render(dot_path, svg_path, timeout, executable),
           {:ok, svg} <- File.read(svg_path) do
        {:ok, %{format: :svg, text: svg, svg: svg, dot: dot}}
      else
        {:error, {:graphviz_failed, _, _}} = error -> error
        {:error, {:graphviz_timeout, _}} = error -> error
        {:error, reason} -> {:error, {:snapshot_io, reason}}
      end
    rescue
      error in ErlangError -> {:error, {:graphviz_failed, Exception.message(error)}}
    after
      File.rm_rf(directory)
    end
  end

  defp write_snapshot_artifacts(snapshot, opts) do
    Enum.reduce_while(@snapshot_artifact_keys, {:ok, snapshot}, fn key, {:ok, current} ->
      content =
        case key do
          :path -> current.text
          :dot_path -> current.dot
          :svg_path -> current.svg
          :json_path -> current.json
          :mermaid_path -> current.mermaid
        end

      case get(opts, key) do
        nil ->
          {:cont, {:ok, current}}

        path ->
          path = Path.expand(path)

          result =
            if is_nil(content),
              do: {:error, {:format_unavailable, key}},
              else: atomic_write(path, content)

          case result do
            :ok ->
              {:cont, {:ok, Map.put(current, key, path)}}

            {:error, reason} ->
              artifacts = Map.take(current, @snapshot_artifact_keys)

              {:halt,
               {:error,
                {:snapshot_io, path, %{reason: reason, snapshot: current, artifacts: artifacts}}}}
          end
      end
    end)
  end

  defp atomic_write(path, content) do
    temporary =
      path <> "." <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false) <> ".tmp"

    try do
      with :ok <- File.mkdir_p(Path.dirname(path)),
           :ok <- File.write(temporary, content, [:exclusive]),
           do: File.rename(temporary, path)
    after
      File.rm(temporary)
    end
  end

  defp snapshot_format(nil), do: "none"
  defp snapshot_format(false), do: "none"
  defp snapshot_format(true), do: "dot"
  defp snapshot_format(format) when format in [:dot, "dot"], do: "dot"
  defp snapshot_format(format) when format in [:json, "json"], do: "json"
  defp snapshot_format(format) when format in [:none, "none"], do: "none"
  defp snapshot_format(other), do: raise(ArgumentError, "unsupported snapshot: #{inspect(other)}")
end
