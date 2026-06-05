defmodule Egglog.Commands do
  @moduledoc """
  Parsed egglog commands.

  `Egglog.Commands` is a small native-backed handle returned by
  `Egglog.parse/1` or `Egglog.Program.parse/1`. Use it when the same command
  sequence will be run repeatedly and you want egglog parsing to happen once.

  The commands are still executed by native egglog; this module only keeps the
  parsed AST resource alive. The original source is retained as well, so
  query-local inspection helpers such as `Egglog.Program.eval/4` and
  `Egglog.Program.lookup/5` can inspect parsed command input without requiring
  callers to keep a second copy of the string.
  """

  alias Egglog.{Common, Native}

  @enforce_keys [:ref, :count]
  defstruct [:ref, :count, :source]

  @opaque t :: %__MODULE__{
            ref: reference(),
            count: non_neg_integer(),
            source: String.t() | nil
          }

  @doc """
  Parses egglog source into a reusable command handle.
  """
  @spec parse(String.t()) :: {:ok, t()} | {:error, term()}
  def parse(source) when is_binary(source) do
    case Native.parse_program(source) do
      {:ok, ref, count} -> {:ok, %__MODULE__{ref: ref, count: count, source: source}}
      {:error, reason, message} -> {:error, {reason, message}}
    end
  end

  @doc """
  Bang variant of `parse/1`.
  """
  @spec parse!(String.t()) :: t()
  def parse!(source) when is_binary(source) do
    source
    |> parse()
    |> Common.bang("failed to parse egglog commands")
  end
end
