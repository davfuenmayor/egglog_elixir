defmodule Egglog.GraphvizTest do
  # PATH is process-wide, so fake renderer tests must not run asynchronously.
  use ExUnit.Case, async: false
  alias Egglog.{EGraph, Program}

  if :os.type() == {:win32, :nt} do
    @moduletag skip: "POSIX renderer probes require /bin/sh and /bin/kill"
  end

  setup %{tmp_dir: dir} do
    previous = System.fetch_env!("PATH")
    System.put_env("PATH", dir <> ":" <> previous)
    on_exit(fn -> System.put_env("PATH", previous) end)
    %{dir: dir}
  end

  @moduletag :tmp_dir

  test "timeout kills the renderer, removes temporary files and retains native handles", %{
    dir: dir
  } do
    marker = Path.join(dir, "renderer")
    fake_dot(dir, "printf '%s\\n' \"$$\" \"$2\" > '#{marker}'\nwhile :; do :; done\n")

    EGraph.with_egraph("(relation seen (i64))\n(seen 1)", fn graph ->
      assert {:error, {:graphviz_timeout, 150}} =
               EGraph.snapshot(graph, render: :svg, render_timeout: 150)

      assert_stopped(marker)
      assert EGraph.num_tuples(graph) == {:ok, 1}
      assert {:ok, %{format: :json}} = EGraph.snapshot(graph, render: :json, render_timeout: 1)
    end)

    Program.with_program("", fn program ->
      assert {:error, {:graphviz_timeout, 150}} =
               Program.snapshot(program, "", %{"render" => "svg", "render_timeout" => "150"})

      assert_stopped(marker)

      assert_raise RuntimeError, ~r/graphviz_timeout/, fn ->
        Program.snapshot!(program, "", render: :svg, render_timeout: 150)
      end

      assert_stopped(marker)
      assert Program.num_tuples(program) == {:ok, 0}
    end)
  end

  test "nonzero exits retain renderer diagnostics", %{dir: dir} do
    fake_dot(dir, "echo 'layout failed' >&2\nexit 7\n")

    EGraph.with_egraph(fn graph ->
      assert {:error, {:graphviz_failed, 7, "layout failed\n"}} =
               EGraph.snapshot(graph, render: :svg)
    end)
  end

  test "auto rendering retains native DOT on renderer failure or timeout", %{dir: dir} do
    fake_dot(dir, "echo 'layout failed' >&2\nexit 7\n")

    EGraph.with_egraph("(relation seen (i64)) (seen 1)", fn graph ->
      assert {:ok, %{format: :dot, text: dot}} = EGraph.snapshot(graph)
      assert dot =~ "digraph"
    end)

    marker = Path.join(dir, "renderer")
    fake_dot(dir, "printf '%s\\n' \"$$\" \"$2\" > '#{marker}'\nwhile :; do :; done\n")

    Program.with_program("", fn program ->
      assert {:ok, %{format: :dot}} = Program.snapshot(program, "", render_timeout: 150)
      assert_stopped(marker)
    end)
  end

  defp fake_dot(dir, body) do
    executable = Path.join(dir, "dot")
    File.write!(executable, "#!/bin/sh\n" <> body)
    File.chmod!(executable, 0o700)
  end

  defp assert_stopped(marker) do
    [pid, input] = marker |> File.read!() |> String.split("\n", trim: true)
    {_message, status} = System.cmd("/bin/kill", ["-0", pid], stderr_to_stdout: true)
    assert status != 0, "renderer #{pid} survived its timeout"
    refute File.exists?(Path.dirname(input))
  end
end
