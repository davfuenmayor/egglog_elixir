defmodule Egglog.GraphvizTest do
  # PATH is process-wide, so fake renderer tests must not run asynchronously.
  use ExUnit.Case, async: false
  alias Egglog.{EGraph, Program}

  if :os.type() == {:win32, :nt} do
    @moduletag skip: "POSIX renderer probes require /bin/sh and /bin/kill"
  end

  setup %{tmp_dir: dir} do
    overrides =
      for key <- ["EGGLOG_GRAPHVIZ_DOT", "GRAPHVIZ_DOT"],
          into: %{},
          do: {key, System.get_env(key)}

    Enum.each(Map.keys(overrides), &System.delete_env/1)

    on_exit(fn ->
      Enum.each(overrides, fn {key, value} ->
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end)
    end)

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

  test "auto selects Mermaid without dot, including string options and exports", %{dir: dir} do
    System.put_env("PATH", dir)
    System.put_env("EGGLOG_GRAPHVIZ_DOT", Path.join(dir, "absent"))
    System.put_env("GRAPHVIZ_DOT", "")
    assert Egglog.Graphviz.executable() == nil

    EGraph.with_egraph("(relation seen (i64)) (seen 1)", fn graph ->
      assert {:ok, %{format: :mermaid, json: json, mermaid: source, dot: nil}} =
               EGraph.snapshot(graph, render: :auto, path: Path.join(dir, "view.mmd"))

      assert Jason.decode!(json)["nodes"] != %{}
      assert source =~ "flowchart"
      assert File.read!(Path.join(dir, "view.mmd")) == source
      assert {:error, {:graphviz_missing, _}} = EGraph.snapshot(graph, render: :svg)
      assert {:ok, %{format: :dot}} = EGraph.snapshot(graph, render: :dot)
    end)

    Program.with_program("", fn program ->
      for render <- [:auto, "auto", true] do
        assert {:ok, %{format: :mermaid}} = Program.snapshot(program, "", render: render)
      end
    end)
  end

  test "auto prefers PATH Graphviz; environment overrides accept executable paths with spaces", %{
    dir: dir
  } do
    fake_dot(dir, "printf '<svg>PATH</svg>' > \"$4\"\n")

    EGraph.with_egraph(fn graph ->
      assert {:ok, %{format: :svg, svg: "<svg>PATH</svg>", dot: dot}} = EGraph.snapshot(graph)
      assert dot =~ "digraph"
      override_dir = Path.join(dir, "graphviz with spaces")
      File.mkdir_p!(override_dir)
      fake_dot(override_dir, "printf '<svg>ENV</svg>' > \"$4\"\n")
      override = Path.join(override_dir, "dot")
      System.put_env("GRAPHVIZ_DOT", override)
      assert Egglog.Graphviz.executable() == override
      assert {:ok, %{svg: "<svg>ENV</svg>"}} = EGraph.snapshot(graph, render: :auto)
      System.put_env("EGGLOG_GRAPHVIZ_DOT", Path.join(dir, "dot"))
      assert {:ok, %{svg: "<svg>PATH</svg>"}} = EGraph.snapshot(graph, render: :svg)
      System.put_env("EGGLOG_GRAPHVIZ_DOT", "not a command --flags")
      assert {:ok, %{svg: "<svg>ENV</svg>"}} = EGraph.snapshot(graph, render: :auto)
      System.put_env("PATH", "")

      Program.with_program("", fn program ->
        assert {:ok, %{format: :svg, svg: "<svg>ENV</svg>"}} =
                 Program.snapshot(program, "", render: :auto)
      end)
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
