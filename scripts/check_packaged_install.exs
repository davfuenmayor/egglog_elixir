# Verify the unpacked Hex package without external tools.
[archive] = System.argv()
{:ok, outer} = :erl_tar.extract(String.to_charlist(archive), [:memory])
{_, contents} = List.keyfind(outer, ~c"contents.tar.gz", 0)

directory =
  Path.join(
    System.tmp_dir!(),
    "egglog-package-#{System.pid()}-#{System.unique_integer([:positive])}"
  )

File.mkdir_p!(directory)

try do
  :ok =
    :erl_tar.extract({:binary, contents}, [:compressed, {:cwd, String.to_charlist(directory)}])

  code = """
  System.put_env("PATH", "")
  Mix.install([{:egglog_elixir, path: #{inspect(directory)}}])
  Code.require_file(#{inspect(Path.join(__DIR__, "check_native.exs"))})

  alias Egglog.Program.Step
  step = Step.next(Step.new(), "(datatype Expr (Num i64)) (Num 1)", render: :auto)
  %{format: :mermaid, mermaid: source} = step.snapshot
  true = String.contains?(source, "flowchart")
  IO.puts("PASS Mermaid output without Graphviz")
  """

  executable = System.find_executable("elixir") || raise "Elixir executable not found"

  {output, status} =
    System.cmd(executable, ["--erl", "+S 2:2", "-e", code],
      stderr_to_stdout: true,
      env: [
        {"EGGLOG_BUILD", nil},
        {"RUSTLER_PRECOMPILED_FORCE_BUILD_ALL", nil},
        {"EGGLOG_GRAPHVIZ_DOT", nil},
        {"GRAPHVIZ_DOT", nil}
      ]
    )

  IO.write(output)
  if status != 0, do: raise("Unpacked package installation failed")
after
  File.rm_rf!(directory)
end
