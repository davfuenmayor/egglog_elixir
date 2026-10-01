defmodule Egglog.GraphvizTest do
  # PATH is process-wide, so fake renderer tests must not run asynchronously.
  use ExUnit.Case, async: false
  alias Egglog.{EGraph, Program}

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
      assert {:error, {:graphviz_timeout, 150}} = EGraph.snapshot(graph, render_timeout: 150)
      assert_stopped(marker)
      assert EGraph.num_tuples(graph) == {:ok, 1}
      assert {:ok, %{format: :json}} = EGraph.snapshot(graph, render: :json, render_timeout: 1)
    end)

    Program.with_program("", fn program ->
      assert {:error, {:graphviz_timeout, 150}} =
               Program.snapshot(program, "", %{"render" => "svg", "render_timeout" => "150"})

      assert_stopped(marker)

      assert_raise RuntimeError, ~r/graphviz_timeout/, fn ->
        Program.snapshot!(program, "", render_timeout: 150)
      end

      assert_stopped(marker)
      assert Program.num_tuples(program) == {:ok, 0}
    end)
  end

  test "nonzero exits retain renderer diagnostics", %{dir: dir} do
    fake_dot(dir, "echo 'layout failed' >&2\nexit 7\n")

    EGraph.with_egraph(fn graph ->
      assert {:error, {:graphviz_failed, 7, "layout failed\n"}} = EGraph.snapshot(graph)
    end)
  end

  test "invalid timeouts are rejected before native input can mutate a graph" do
    EGraph.with_egraph(fn graph ->
      for timeout <- [0, -1, nil, :infinity, "bad", 4_294_967_296] do
        assert {:error, {:invalid_option, _}} = EGraph.snapshot(graph, render_timeout: timeout)
      end

      assert EGraph.num_tuples(graph) == {:ok, 0}

      assert {:error, {:invalid_option, _}} =
               EGraph.run(graph, "(relation added ())", render_timeout: 1)
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
