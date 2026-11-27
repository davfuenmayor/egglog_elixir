defmodule Egglog.GraphvizTest do
  # PATH is process-wide, so fake renderer tests must not run asynchronously.
  use ExUnit.Case, async: false
  alias Egglog.{EGraph, Program}

  @windows :os.type() == {:win32, :nt}

  setup do
    variables = ~w(PATH EGGLOG_GRAPHVIZ_DOT GRAPHVIZ_DOT)
    saved = Map.new(variables, &{&1, System.get_env(&1)})
    Enum.each(tl(variables), &System.delete_env/1)

    on_exit(fn ->
      Enum.each(saved, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end)
  end

  @moduletag :tmp_dir

  @tag skip: @windows
  test "timeout kills the renderer, removes temporary files and preserves graph state", %{
    tmp_dir: dir
  } do
    marker = Path.join(dir, "renderer")
    fake_dot(dir, "printf '%s\n' \"$$\" \"$2\" > '#{marker}'\nwhile :; do :; done\n")
    System.put_env("EGGLOG_GRAPHVIZ_DOT", Path.join(dir, "dot"))

    EGraph.with_egraph("(relation seen (i64)) (seen 1)", fn graph ->
      assert {:error, {:graphviz_timeout, 1_000}} =
               EGraph.snapshot(graph, render: :svg, render_timeout: 1_000)

      assert_stopped(marker)
      assert {:ok, true} = EGraph.check(graph, "(seen 1)")
    end)
  end

  @tag skip: @windows
  test "explicit SVG reports renderer diagnostics and automatic rendering keeps DOT", %{
    tmp_dir: dir
  } do
    fake_dot(dir, "echo 'layout failed' >&2\nexit 7\n")
    System.put_env("EGGLOG_GRAPHVIZ_DOT", Path.join(dir, "dot"))

    EGraph.with_egraph("(datatype T (Example)) (Example)", fn graph ->
      assert {:error, {:graphviz_failed, 7, "layout failed\n"}} =
               EGraph.snapshot(graph, render: :svg)

      assert {:ok, %{format: :dot, text: dot}} = EGraph.snapshot(graph, render: :auto)
      assert dot =~ "Example"
    end)
  end

  test "auto selects Mermaid without dot, including string options and exports", %{tmp_dir: dir} do
    System.put_env("PATH", dir)
    System.put_env("EGGLOG_GRAPHVIZ_DOT", Path.join(dir, "absent"))
    System.put_env("GRAPHVIZ_DOT", "")
    assert Egglog.Graphviz.executable() == nil

    EGraph.with_egraph("(relation seen (i64)) (seen 1)", fn graph ->
      assert {:ok, %{format: :mermaid, json: json, mermaid: source, dot: dot}} =
               EGraph.snapshot(graph, render: :auto, path: Path.join(dir, "view.mmd"))

      assert dot =~ "digraph"
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

  @tag skip: @windows
  test "auto prefers PATH Graphviz; environment overrides accept executable paths with spaces", %{
    tmp_dir: dir
  } do
    System.put_env("PATH", dir <> ":" <> System.fetch_env!("PATH"))
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
