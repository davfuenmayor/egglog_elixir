defmodule Egglog do
  @moduledoc """
  Thin Elixir facade for native egglog.

  Load a reusable native program with `Egglog.Program.load/2`, then run
  query-local facts, commands, requests, and a budget with
  `Egglog.Program.run/3`.

  For interactive workflows where native egglog state should persist across
  calls, use `Egglog.EGraph`. It owns one mutable native session process and
  exposes native `push`/`pop` rollback points.
  """

  alias Egglog.Program

  @doc """
  Parses egglog source into a reusable `Egglog.Commands` handle.

  Parsed commands are useful when the same command sequence is executed
  repeatedly.
  """
  @spec parse(String.t()) :: {:ok, Egglog.Commands.t()} | {:error, term()}
  defdelegate parse(source), to: Program

  @doc """
  Bang variant of `parse/1`.
  """
  @spec parse!(String.t()) :: Egglog.Commands.t()
  defdelegate parse!(source), to: Program

  @doc """
  Loads a reusable query-local program.

  Query-local facts and temporary commands do not mutate the loaded base.
  Concurrent calls against the same loaded program are serialized by that
  native resource; independent loaded programs can run independently.

  See `Egglog.Program.load/2` for supported options and defaults.
  """
  @spec load(String.t() | map(), keyword() | map()) :: {:ok, Program.t()} | {:error, term()}
  defdelegate load(theory_spec, opts \\ []), to: Program

  @doc """
  Bang variant of `load/2`.
  """
  @spec load!(String.t() | map(), keyword() | map()) :: Program.t()
  defdelegate load!(theory_spec, opts \\ []), to: Program

  @doc """
  Runs query-local egglog input against a loaded program.

  See `Egglog.Program.run/3` for the structured input fields accepted by this
  facade, supported options, and defaults.
  """
  @spec run(Program.t(), Program.input(), keyword() | map()) ::
          {:ok, Program.run_result()} | {:error, term()}
  defdelegate run(program, input, opts \\ []), to: Program

  @doc """
  Bang variant of `run/3`.
  """
  @spec run!(Program.t(), Program.input(), keyword() | map()) :: Program.run_result()
  defdelegate run!(program, input, opts \\ []), to: Program

  @doc """
  Runs a native egglog `(check ...)` and returns `{:ok, true}` or
  `{:ok, false}`.

  See `Egglog.Program.check/4` for supported options and defaults.
  """
  @spec check(Program.t(), Program.input(), String.t(), keyword() | map()) ::
          {:ok, boolean()} | {:error, term()}
  defdelegate check(program, input, fact, opts \\ []), to: Program

  @doc """
  Boolean variant of `check/4`.

  See `Egglog.Program.check?/4` for supported options and defaults.
  """
  @spec check?(Program.t(), Program.input(), String.t(), keyword() | map()) :: boolean()
  defdelegate check?(program, input, fact, opts \\ []), to: Program

  @doc """
  Asserts that a native egglog check fails.

  See `Egglog.Program.check_fail/4` for supported options and defaults.
  """
  @spec check_fail(Program.t(), Program.input(), String.t(), keyword() | map()) ::
          :ok | {:error, term()}
  defdelegate check_fail(program, input, fact, opts \\ []), to: Program

  @doc """
  Extracts the cheapest native egglog term for an expression.

  See `Egglog.Program.extract/4` for supported options and defaults.
  """
  @spec extract(Program.t(), Program.input(), String.t(), keyword() | map()) ::
          {:ok, String.t()} | {:error, term()}
  defdelegate extract(program, input, expr, opts \\ []), to: Program

  @doc """
  Bang variant of `extract/4`.

  See `Egglog.Program.extract!/4` for supported options and defaults.
  """
  @spec extract!(Program.t(), Program.input(), String.t(), keyword() | map()) :: String.t()
  defdelegate extract!(program, input, expr, opts \\ []), to: Program

  @doc """
  Evaluates an egglog expression after applying query-local input.

  Primitive native values are decoded to Elixir values; e-class values are
  returned as `%{sort: sort, type: :value, value: text}`.

  See `Egglog.Program.eval/4` for supported options and defaults.
  """
  @spec eval(Program.t(), Program.input(), String.t(), keyword() | map()) ::
          {:ok, Program.value()} | {:error, term()}
  defdelegate eval(program, input, expr, opts \\ []), to: Program

  @doc """
  Bang variant of `eval/4`.

  See `Egglog.Program.eval!/4` for supported options and defaults.
  """
  @spec eval!(Program.t(), Program.input(), String.t(), keyword() | map()) :: Program.value()
  defdelegate eval!(program, input, expr, opts \\ []), to: Program

  @doc """
  Looks up a function row after evaluating the given argument expressions.

  Returns `{:ok, nil}` when the table has no row for the evaluated key.

  See `Egglog.Program.lookup/5` for supported options and defaults.
  """
  @spec lookup(Program.t(), Program.input(), String.t(), [String.t()], keyword() | map()) ::
          {:ok, Program.value() | nil} | {:error, term()}
  defdelegate lookup(program, input, name, arg_exprs, opts \\ []), to: Program

  @doc """
  Bang variant of `lookup/5`.

  See `Egglog.Program.lookup!/5` for supported options and defaults.
  """
  @spec lookup!(Program.t(), Program.input(), String.t(), [String.t()], keyword() | map()) ::
          Program.value() | nil
  defdelegate lookup!(program, input, name, arg_exprs, opts \\ []), to: Program

  @doc """
  Builds a query-local DOT/SVG/JSON snapshot.

  See `Egglog.Program.snapshot/3` for supported options and defaults.
  """
  @spec snapshot(Program.t(), Program.input(), keyword() | map()) ::
          {:ok, map()} | {:error, term()}
  defdelegate snapshot(program, input, opts \\ []), to: Program

  @doc """
  Bang variant of `snapshot/3`.

  See `Egglog.Program.snapshot!/3` for supported options and defaults.
  """
  @spec snapshot!(Program.t(), Program.input(), keyword() | map()) :: map()
  defdelegate snapshot!(program, input, opts \\ []), to: Program

  @doc """
  Returns native egglog's tuple count for the loaded program.

  See `Egglog.Program.num_tuples/1` for details.
  """
  @spec num_tuples(Program.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  defdelegate num_tuples(program), to: Program

  @doc """
  Closes the loaded program.
  """
  @spec close(Program.t()) :: :ok | {:error, term()}
  defdelegate close(program), to: Program
end
