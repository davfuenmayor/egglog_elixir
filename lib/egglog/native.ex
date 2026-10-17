defmodule Egglog.Native do
  @moduledoc false

  @on_load :load_nif

  def load_nif do
    path = Application.app_dir(:egglog_elixir, "priv/native/egglog_nif")
    :erlang.load_nif(path |> String.to_charlist() |> :filename.nativename(), 0)
  end

  def parse_program(_source), do: :erlang.nif_error(:nif_not_loaded)
  def load_program(_source, _proofs?, _num_threads), do: :erlang.nif_error(:nif_not_loaded)
  def new_egraph(_source, _proofs?, _num_threads), do: :erlang.nif_error(:nif_not_loaded)

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
  def functions_program(_program), do: :erlang.nif_error(:nif_not_loaded)
  def functions_egraph(_graph), do: :erlang.nif_error(:nif_not_loaded)
  def function_program(_program, _name), do: :erlang.nif_error(:nif_not_loaded)
  def function_egraph(_graph, _name), do: :erlang.nif_error(:nif_not_loaded)
  def clear_function_egraph(_graph, _name), do: :erlang.nif_error(:nif_not_loaded)
  def query_program(_program, _source, _vars, _facts), do: :erlang.nif_error(:nif_not_loaded)
  def query_egraph(_graph, _vars, _facts), do: :erlang.nif_error(:nif_not_loaded)
  def program_num_threads(_program), do: :erlang.nif_error(:nif_not_loaded)
  def egraph_num_threads(_graph), do: :erlang.nif_error(:nif_not_loaded)
  def set_egraph_num_threads(_graph, _count), do: :erlang.nif_error(:nif_not_loaded)
end
