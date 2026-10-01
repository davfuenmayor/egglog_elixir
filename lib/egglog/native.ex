defmodule Egglog.Native do
  @moduledoc false

  @build_from_source Application.compile_env(:egglog_elixir, :build_from_source, true) or
                       System.get_env("RUSTLER_PRECOMPILED_FORCE_BUILD_ALL") in ["1", "true"] or
                       Application.compile_env(:rustler_precompiled, :force_build_all, false) or
                       Application.compile_env(
                         :rustler_precompiled,
                         [:force_build, :egglog_elixir],
                         false
                       )

  if @build_from_source do
    # Validate resolution before Rustler invokes Cargo without --locked.
    case System.cmd("cargo", ["metadata", "--locked", "--format-version=1"],
           cd: Path.expand("../../native/egglog_nif", __DIR__)
         ) do
      {_metadata, 0} -> :ok
      {output, _status} -> raise "locked native dependency resolution failed:\n#{output}"
    end

    use Rustler, otp_app: :egglog_elixir, crate: "egglog_nif", mode: :release
  else
    use RustlerPrecompiled,
      otp_app: :egglog_elixir,
      crate: "egglog_nif",
      base_url:
        Application.compile_env(
          :egglog_elixir,
          :precompiled_url,
          "https://github.com/davfuenmayor/egglog_elixir/releases/download/v#{Mix.Project.config()[:version]}"
        )
        |> String.trim_trailing("/")
        |> Kernel.<>("/"),
      version: Mix.Project.config()[:version],
      targets: ["x86_64-unknown-linux-gnu"],
      nif_versions: ["2.15"]
  end

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
