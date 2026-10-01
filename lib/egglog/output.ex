defmodule Egglog.Output do
  @moduledoc """
  Displays text returned by native egglog, without interpreting submitted source.

  Successful commands can be silent. An empty output list does not imply that
  nothing happened; inspect the run result or use the native check/query APIs.
  """

  @doc "Returns nonempty native output text, optionally filtered by output type."
  def texts(%{outputs: outputs}, type \\ :all) do
    for %{type: output_type, text: text} <- outputs,
        type == :all or type == output_type,
        is_binary(text),
        text = String.trim_trailing(text),
        text != "",
        do: text
  end

  @doc "Prints native output text to the current IO device. Returns `:ok`."
  def print(result, type \\ :all), do: Enum.each(texts(result, type), &IO.puts/1)
end
