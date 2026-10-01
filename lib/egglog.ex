defmodule Egglog do
  @moduledoc """
  Thin Elixir facade for native egglog.

  Load a reusable native program with `Egglog.Program.load/2`, then run
  query-local facts, commands, requests, and a budget with
  `Egglog.Program.run/3`.

  For interactive workflows where native egglog state should persist across
  calls, use `Egglog.EGraph`. It owns one mutable native session process and
  exposes native `push`/`pop` rollback points.

  Scoped use closes native resources even when the callback raises:

      iex> Egglog.Program.with_program("", fn program ->
      ...>   Egglog.Program.eval(program, "", "(+ 1 2)")
      ...> end)
      {:ok, %{sort: "i64", type: :integer, value: 3}}

  Native command text and schedules remain egglog's own language; the wrapper
  does not implement an optimizer or a second execution engine.
  """

  alias Egglog.Program

  @doc "Loads a program, returns the callback result, and closes it on success or failure. See `Egglog.Program.with_program/3`."
  defdelegate with_program(source, fun, opts \\ []), to: Program

  @doc """
  Parses egglog source into a reusable `Egglog.Commands` handle.

  Parsed commands are useful when the same command sequence is executed
  repeatedly.
  """
  defdelegate parse(source), to: Program

  @doc """
  Bang variant of `parse/1`.
  """
  defdelegate parse!(source), to: Program

  @doc """
  Loads a reusable query-local program.

  Query-local facts and temporary commands do not mutate the loaded base.
  Concurrent calls against the same loaded program are serialized by that
  native resource; independent loaded programs can run independently.

  See `Egglog.Program.load/2` for supported options and defaults.
  """
  defdelegate load(theory_spec, opts \\ []), to: Program

  @doc """
  Bang variant of `load/2`.
  """
  defdelegate load!(theory_spec, opts \\ []), to: Program

  @doc """
  Runs query-local egglog input against a loaded program.

  See `Egglog.Program.run/3` for the structured input fields accepted by this
  facade, supported options, and defaults.
  """
  defdelegate run(program, input, opts \\ []), to: Program

  @doc """
  Bang variant of `run/3`.
  """
  defdelegate run!(program, input, opts \\ []), to: Program

  @doc """
  Runs a native egglog `(check ...)` and returns `{:ok, true}` or
  `{:ok, false}`.

  See `Egglog.Program.check/4` for supported options and defaults.
  """
  defdelegate check(program, input, fact, opts \\ []), to: Program

  @doc """
  Boolean variant of `check/4`.

  See `Egglog.Program.check?/4` for supported options and defaults.
  """
  defdelegate check?(program, input, fact, opts \\ []), to: Program

  @doc """
  Asserts that a native egglog check fails.

  See `Egglog.Program.check_fail/4` for supported options and defaults.
  """
  defdelegate check_fail(program, input, fact, opts \\ []), to: Program

  @doc """
  Extracts the cheapest native egglog term for an expression.

  See `Egglog.Program.extract/4` for supported options and defaults.
  """
  defdelegate extract(program, input, expr, opts \\ []), to: Program

  @doc """
  Bang variant of `extract/4`.

  See `Egglog.Program.extract!/4` for supported options and defaults.
  """
  defdelegate extract!(program, input, expr, opts \\ []), to: Program

  @doc """
  Evaluates an egglog expression after applying query-local input.

  Primitive native values are decoded to Elixir values; e-class values are
  returned as `%{sort: sort, type: :value, value: text}`.

  See `Egglog.Program.eval/4` for supported options and defaults.
  """
  defdelegate eval(program, input, expr, opts \\ []), to: Program

  @doc """
  Bang variant of `eval/4`.

  See `Egglog.Program.eval!/4` for supported options and defaults.
  """
  defdelegate eval!(program, input, expr, opts \\ []), to: Program

  @doc """
  Looks up a function row after evaluating the given argument expressions.

  Returns `{:ok, nil}` when the table has no row for the evaluated key.

  See `Egglog.Program.lookup/5` for supported options and defaults.
  """
  defdelegate lookup(program, input, name, arg_exprs, opts \\ []), to: Program

  @doc """
  Bang variant of `lookup/5`.

  See `Egglog.Program.lookup!/5` for supported options and defaults.
  """
  defdelegate lookup!(program, input, name, arg_exprs, opts \\ []), to: Program

  @doc """
  Builds a query-local DOT/SVG/JSON snapshot.

  See `Egglog.Program.snapshot/3` for supported options and defaults.
  """
  defdelegate snapshot(program, input, opts \\ []), to: Program

  @doc """
  Bang variant of `snapshot/3`.

  See `Egglog.Program.snapshot!/3` for supported options and defaults.
  """
  defdelegate snapshot!(program, input, opts \\ []), to: Program

  @doc """
  Returns native egglog's tuple count for the loaded program.

  See `Egglog.Program.num_tuples/1` for details.
  """
  defdelegate num_tuples(program), to: Program

  @doc """
  Closes the loaded program.
  """
  defdelegate close(program), to: Program
end
