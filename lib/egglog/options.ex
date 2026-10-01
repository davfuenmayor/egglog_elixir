defmodule Egglog.Options do
  @moduledoc false

  @snapshot [
    :snapshot,
    :snapshot_max_functions,
    :snapshot_max_calls_per_function,
    :snapshot_inline_leaves,
    :snapshot_split_primitive_outputs
  ]
  @run @snapshot ++ [:output_limit]
  @artifacts [:render, :render_timeout, :path, :dot_path, :svg_path, :json_path]
  @input [
           :source,
           :program,
           :commands,
           :facts,
           :terms,
           :sets,
           :unions,
           :requests,
           :schedule,
           :mode,
           :budget
         ] ++ @snapshot
  @profiles %{
    graph_load: [:name, :proofs, :num_threads],
    program_load: [:name, :proofs, :modes, :default_budget, :num_threads],
    graph_run: @run,
    program_run: @run ++ [:mode, :budget],
    graph_snapshot: @run ++ @artifacts,
    program_snapshot: @run ++ @artifacts ++ [:mode, :budget],
    graph_extract: @run ++ [:variants],
    program_extract: @run ++ [:variants, :mode, :budget],
    program_query: [:mode, :budget],
    thread_settings: [:num_threads]
  }

  def with_options(opts, profile, fun) do
    with {:ok, opts} <- validate(opts, Map.fetch!(@profiles, profile)), do: fun.(opts)
  end

  def input(source) when is_binary(source), do: {:ok, %{source: source}}
  def input(commands) when is_list(commands), do: validate(%{commands: commands}, @input)
  def input(input) when is_map(input), do: validate(input, @input)
  def input(_), do: invalid("input must be source, commands, or a map")

  def validate(opts, keys) when is_list(opts) or is_map(opts) do
    Enum.reduce_while(opts, {:ok, %{}}, fn
      {original_key, value}, {:ok, acc} ->
        key = Enum.find(keys, &(original_key == &1 or original_key == Atom.to_string(&1)))

        cond do
          is_nil(key) ->
            {:halt, invalid("unknown option #{inspect(original_key)}")}

          Map.has_key?(acc, key) ->
            {:halt, invalid("duplicate option #{key}")}

          true ->
            case normalize(key, value) do
              {:ok, value} -> {:cont, {:ok, Map.put(acc, key, value)}}
              :error -> {:halt, invalid("invalid #{key}")}
              {:error, _} = error -> {:halt, error}
            end
        end

      _, _ ->
        {:halt, invalid("options must contain key/value pairs")}
    end)
  end

  def validate(_, _), do: invalid("options must be a keyword list or map")

  defp normalize(key, value) when key in [:budget, :default_budget],
    do: validate(value, [:rounds, :output_limit])

  defp normalize(key, value) when key in [:proofs, :snapshot_split_primitive_outputs] do
    case value do
      value when value in [true, "true", "1", 1] -> {:ok, true}
      value when value in [false, "false", "0", 0] -> {:ok, false}
      _ -> :error
    end
  end

  defp normalize(key, value)
       when key in [
              :num_threads,
              :rounds,
              :snapshot_max_functions,
              :snapshot_max_calls_per_function,
              :snapshot_inline_leaves
            ],
       do: count(value, 0)

  defp normalize(:output_limit, nil), do: {:ok, nil}

  defp normalize(:render_timeout, value) do
    with {:ok, milliseconds} <- count(value, 1) do
      if milliseconds <= 4_294_967_295, do: {:ok, milliseconds}, else: :error
    end
  end

  defp normalize(key, value) when key in [:output_limit, :variants, :count],
    do: count(value, 1)

  defp normalize(:snapshot, value)
       when value in [nil, false, true, :none, :dot, :json, "none", "dot", "json"],
       do: {:ok, value}

  defp normalize(:render, value)
       when value in [nil, false, true, :auto, :dot, :svg, :json, "auto", "dot", "svg", "json"],
       do: {:ok, value}

  defp normalize(:mode, value) when is_atom(value) or is_binary(value), do: {:ok, value}

  defp normalize(key, nil) when key in [:name, :path, :dot_path, :svg_path, :json_path],
    do: {:ok, nil}

  defp normalize(key, value)
       when key in [:name, :path, :dot_path, :svg_path, :json_path, :source, :program, :schedule] and
              is_binary(value),
       do: {:ok, value}

  defp normalize(:modes, value) when is_map(value) do
    if Enum.all?(value, fn {key, schedule} ->
         (is_atom(key) or is_binary(key)) and is_binary(schedule)
       end), do: {:ok, value}, else: :error
  end

  defp normalize(key, value) when key in [:commands, :facts] and is_list(value) do
    if Enum.all?(List.flatten(value), &(is_binary(&1) or is_nil(&1))),
      do: {:ok, value},
      else: :error
  end

  defp normalize(:terms, value) when is_map(value) do
    if Enum.all?(value, fn {key, expr} -> is_binary(key) and is_binary(expr) end),
      do: {:ok, value},
      else: :error
  end

  defp normalize(key, value) when key in [:sets, :unions] and is_list(value) do
    if Enum.all?(value, fn
         {left, right} -> is_binary(left) and is_binary(right)
         _ -> false
       end), do: {:ok, value}, else: :error
  end

  defp normalize(:requests, requests) when is_list(requests) do
    Enum.reduce_while(requests, {:ok, []}, fn request, {:ok, acc} ->
      case request(request) do
        {:ok, request} -> {:cont, {:ok, [request | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, requests} -> {:ok, Enum.reverse(requests)}
      error -> error
    end
  end

  defp normalize(:type, value)
       when value in [
              :check,
              :extract,
              :print_size,
              :print_function,
              "check",
              "extract",
              "print_size",
              "print_function",
              "print-function"
            ],
       do: {:ok, value}

  defp normalize(:expr, value) when is_binary(value), do: {:ok, value}
  defp normalize(:limit, value), do: count(value, 1)
  defp normalize(_, _), do: :error

  defp request(source) when is_binary(source), do: {:ok, source}

  defp request(request) do
    with {:ok, request} <- validate(request, [:type, :expr, :name, :variants, :limit]),
         type when not is_nil(type) <- Map.get(request, :type) do
      required =
        case type do
          type when type in [:check, :extract, "check", "extract"] -> :expr
          type when type in [:print_function, "print_function", "print-function"] -> :name
          _ -> nil
        end

      if is_nil(required) or is_binary(Map.get(request, required)),
        do: {:ok, request},
        else: invalid("request requires #{required}")
    else
      nil -> invalid("request requires type")
      error -> error
    end
  end

  defp count(value, minimum) when is_binary(value) do
    case Integer.parse(value) do
      {value, ""} -> count(value, minimum)
      _ -> :error
    end
  end

  defp count(value, minimum)
       when is_integer(value) and value >= minimum and value <= 9_223_372_036_854_775_807,
       do: {:ok, value}

  defp count(_, _), do: :error
  defp invalid(message), do: {:error, {:invalid_option, message}}
end
