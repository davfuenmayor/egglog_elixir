defmodule Egglog.Native do
  @moduledoc false

  use Rustler, otp_app: :egglog_elixir, crate: "egglog_nif"

  def parse_program(_source), do: :erlang.nif_error(:nif_not_loaded)
  def load_program(_source, _proofs?), do: :erlang.nif_error(:nif_not_loaded)
  def new_egraph(_source, _proofs?), do: :erlang.nif_error(:nif_not_loaded)

  def run_program(
        _program,
        _source,
        _mode,
        _snapshot_format,
        _snapshot_max_functions,
        _snapshot_max_calls_per_function,
        _snapshot_inline_leaves,
        _snapshot_split_primitive_outputs?
      ),
      do: :erlang.nif_error(:nif_not_loaded)

  def run_parsed_program(
        _program,
        _commands,
        _mode,
        _snapshot_format,
        _snapshot_max_functions,
        _snapshot_max_calls_per_function,
        _snapshot_inline_leaves,
        _snapshot_split_primitive_outputs?
      ),
      do: :erlang.nif_error(:nif_not_loaded)

  def run_egraph(
        _egraph,
        _program,
        _snapshot_format,
        _snapshot_max_functions,
        _snapshot_max_calls_per_function,
        _snapshot_inline_leaves,
        _snapshot_split_primitive_outputs?
      ),
      do: :erlang.nif_error(:nif_not_loaded)

  def run_parsed_egraph(
        _egraph,
        _commands,
        _snapshot_format,
        _snapshot_max_functions,
        _snapshot_max_calls_per_function,
        _snapshot_inline_leaves,
        _snapshot_split_primitive_outputs?
      ),
      do: :erlang.nif_error(:nif_not_loaded)

  def eval_program(_program, _source, _expr), do: :erlang.nif_error(:nif_not_loaded)
  def eval_egraph(_egraph, _expr), do: :erlang.nif_error(:nif_not_loaded)
  def lookup_program(_program, _source, _name, _arg_exprs), do: :erlang.nif_error(:nif_not_loaded)
  def lookup_egraph(_egraph, _name, _arg_exprs), do: :erlang.nif_error(:nif_not_loaded)

  def program_num_tuples(_program), do: :erlang.nif_error(:nif_not_loaded)
  def egraph_num_tuples(_egraph), do: :erlang.nif_error(:nif_not_loaded)
  def close_program(_program), do: :erlang.nif_error(:nif_not_loaded)
  def close_egraph(_egraph), do: :erlang.nif_error(:nif_not_loaded)
end
