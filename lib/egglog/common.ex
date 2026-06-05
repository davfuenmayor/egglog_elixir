defmodule Egglog.Common do
  @moduledoc false

  @snapshot_artifact_keys [:render, :path, :dot_path, :svg_path, :json_path]

  def from_native_load({:ok, ref}), do: {:ok, ref}
  def from_native_load({:error, reason, message}), do: {:error, {reason, message}}

  def from_native_result({:error, reason, message}, _limit), do: {:error, {reason, message}}

  def from_native_result(
        {:ok, status, outputs, numeric_stats, text_stats, snapshot, report},
        limit
      ) do
    {outputs, limited?} = limit_outputs(outputs, limit)
    {snapshot_format, snapshot_text, snapshot_omitted, snapshot_stats} = snapshot

    result = %{
      status: if(limited?, do: :limit, else: status),
      outputs:
        Enum.map(outputs, fn {type, text} -> %{type: String.to_atom(type), text: text} end),
      stats: stats(numeric_stats ++ snapshot_stats, text_stats),
      report: report(report)
    }

    {:ok, put_snapshot(result, snapshot_format, snapshot_text, snapshot_omitted)}
  end

  def from_native_close(:ok), do: :ok
  def from_native_close({:error, reason, message}), do: {:error, {reason, message}}

  def from_native_value({:ok, sort, kind, value}), do: {:ok, value(sort, kind, value)}
  def from_native_value({:error, reason, message}), do: {:error, {reason, message}}

  def from_native_lookup({:ok, false, _sort, _kind, _value}), do: {:ok, nil}
  def from_native_lookup({:ok, true, sort, kind, value}), do: {:ok, value(sort, kind, value)}
  def from_native_lookup({:error, reason, message}), do: {:error, {reason, message}}

  def from_native_count({:ok, count}), do: {:ok, count}
  def from_native_count({:error, reason, message}), do: {:error, {reason, message}}

  def snapshot_from_result(%{snapshot: native_snapshot, stats: stats} = result, opts, render) do
    with {:ok, rendered} <- render_snapshot(native_snapshot.text, native_snapshot.format, render) do
      snapshot =
        %{
          format: rendered.format,
          text: rendered.text,
          dot: Map.get(rendered, :dot),
          svg: Map.get(rendered, :svg),
          json: Map.get(rendered, :json),
          omitted: native_snapshot.omitted,
          stats: Map.take(stats, [:snapshot_nodes, :snapshot_classes]),
          result: result
        }
        |> write_snapshot_artifacts(opts)

      {:ok, snapshot}
    end
  end

  def snapshot_from_result(_result, _opts, _render), do: {:error, :missing_snapshot}

  def snapshot_options(opts, input \\ %{}) do
    %{
      format: get(opts, :snapshot, get(input, :snapshot, :none)) |> snapshot_format(),
      max_functions:
        get(opts, :snapshot_max_functions, get(input, :snapshot_max_functions, 0))
        |> nonnegative_integer(),
      max_calls_per_function:
        get(
          opts,
          :snapshot_max_calls_per_function,
          get(input, :snapshot_max_calls_per_function, 0)
        )
        |> nonnegative_integer(),
      inline_leaves:
        get(opts, :snapshot_inline_leaves, get(input, :snapshot_inline_leaves, 0))
        |> nonnegative_integer(),
      split_primitive_outputs?:
        get(
          opts,
          :snapshot_split_primitive_outputs,
          get(input, :snapshot_split_primitive_outputs, false)
        )
        |> truthy?()
    }
  end

  def native_snapshot_format(render) when render in [:json, "json"], do: :json
  def native_snapshot_format(_render), do: :dot

  def snapshot_run_opts(opts) do
    render = get(opts, :render, :auto)

    run_opts =
      opts
      |> Map.drop(@snapshot_artifact_keys)
      |> Map.put(:snapshot, native_snapshot_format(render))

    {render, run_opts}
  end

  def check_result({:ok, _result}), do: {:ok, true}

  def check_result({:error, {:native_error, message}})
      when is_binary(message) do
    if String.contains?(message, "Check failed"),
      do: {:ok, false},
      else: {:error, {:native_error, message}}
  end

  def check_result({:error, reason}), do: {:error, reason}

  def ok_only({:ok, _result}), do: :ok
  def ok_only({:error, reason}), do: {:error, reason}

  def extract_request(expr, opts) do
    case get(option_map(opts), :variants) do
      nil -> "(extract #{expr})"
      variants -> "(extract #{expr} #{variants})"
    end
  end

  def extraction({:ok, result}) do
    text =
      result.outputs
      |> Enum.filter(&(&1.type in [:extract, :extract_variants]))
      |> Enum.map_join(& &1.text)
      |> String.trim_trailing("\n")

    {:ok, text}
  end

  def extraction({:error, reason}), do: {:error, reason}

  def bang({:ok, value}, _message), do: value
  def bang({:error, reason}, message), do: raise("#{message}: #{inspect(reason)}")

  def join_commands(commands) when is_list(commands) do
    commands
    |> List.flatten()
    |> Enum.reject(&blank?/1)
    |> Enum.join("\n")
  end

  def option_map(opts) when is_map(opts), do: opts
  def option_map(opts) when is_list(opts), do: Map.new(opts)

  def get(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end

  def required!(map, key),
    do: get(map, key) || raise(ArgumentError, "missing required key #{inspect(key)}")

  def positive_integer(value) when is_integer(value) and value > 0, do: value

  def positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> nil
    end
  end

  def positive_integer(_value), do: nil

  def nonnegative_integer(value) when is_integer(value) and value >= 0, do: value

  def nonnegative_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int >= 0 -> int
      _ -> 0
    end
  end

  def nonnegative_integer(_value), do: 0

  def blank?(nil), do: true
  def blank?(value) when is_binary(value), do: String.trim(value) == ""
  def blank?(_value), do: false

  def truthy?(value), do: value in [true, "true", "1", 1]

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

  defp limit_outputs(outputs, limit) do
    case positive_integer(limit) do
      nil -> {outputs, false}
      limit -> {Enum.take(outputs, limit), length(outputs) > limit}
    end
  end

  defp put_snapshot(result, "", _text, _omitted), do: result
  defp put_snapshot(result, "none", _text, _omitted), do: result

  defp put_snapshot(result, format, text, omitted) do
    Map.put(result, :snapshot, %{format: String.to_atom(format), text: text, omitted: omitted})
  end

  defp render_snapshot(json, :json, render) when render in [:json, "json"] do
    {:ok, %{format: :json, text: json, json: json}}
  end

  defp render_snapshot(text, format, _render) when format != :dot do
    {:ok, %{format: format, text: text}}
  end

  defp render_snapshot(dot, :dot, render) when render in [:dot, "dot", false, nil] do
    {:ok, %{format: :dot, text: dot, dot: dot}}
  end

  defp render_snapshot(dot, :dot, render) when render in [:auto, "auto", :svg, "svg", true] do
    case System.find_executable("dot") do
      nil when render in [:auto, "auto", true] ->
        {:ok, %{format: :dot, text: dot, dot: dot}}

      nil ->
        {:error, {:graphviz_missing, "could not find dot executable on PATH"}}

      _dot ->
        render_svg(dot)
    end
  end

  defp render_snapshot(_text, _format, render), do: {:error, {:unsupported_render, render}}

  defp render_svg(dot) do
    dot_path = Path.join(System.tmp_dir!(), "egglog-#{System.unique_integer([:positive])}.dot")
    svg_path = Path.rootname(dot_path) <> ".svg"

    try do
      File.write!(dot_path, dot)

      case System.cmd("dot", ["-Tsvg", dot_path, "-o", svg_path], stderr_to_stdout: true) do
        {_output, 0} ->
          svg = File.read!(svg_path)
          {:ok, %{format: :svg, text: svg, svg: svg, dot: dot}}

        {output, status} ->
          {:error, {:graphviz_failed, status, output}}
      end
    after
      File.rm(dot_path)
      File.rm(svg_path)
    end
  end

  defp write_snapshot_artifacts(snapshot, opts) do
    snapshot
    |> maybe_write(:dot_path, snapshot.dot, opts)
    |> maybe_write(:svg_path, Map.get(snapshot, :svg), opts)
    |> maybe_write(:json_path, Map.get(snapshot, :json), opts)
    |> maybe_write(:path, snapshot.text, opts)
  end

  defp maybe_write(snapshot, key, content, opts) do
    case get(opts, key) do
      nil -> snapshot
      _path when is_nil(content) -> Map.put(snapshot, key, nil)
      path -> write_file(snapshot, key, path, content)
    end
  end

  defp write_file(snapshot, key, path, content) do
    path = Path.expand(path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    Map.put(snapshot, key, path)
  end

  defp snapshot_format(nil), do: "none"
  defp snapshot_format(false), do: "none"
  defp snapshot_format(true), do: "dot"
  defp snapshot_format(format) when format in [:dot, "dot"], do: "dot"
  defp snapshot_format(format) when format in [:json, "json"], do: "json"
  defp snapshot_format(format) when format in [:none, "none"], do: "none"
  defp snapshot_format(other), do: raise(ArgumentError, "unsupported snapshot: #{inspect(other)}")
end
