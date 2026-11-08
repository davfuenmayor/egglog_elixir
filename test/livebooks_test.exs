defmodule Egglog.LivebooksTest do
  use ExUnit.Case, async: true
  @root Path.expand("../livebooks", __DIR__)

  test "executable notebooks install this checkout; index lists every notebook" do
    notebooks = Path.wildcard(Path.join(@root, "**/*.livemd"))
    assert length(notebooks) == 8

    index_path = Path.join(@root, "index.livemd")
    index = File.read!(index_path)
    refute index =~ "```elixir"

    for path <- notebooks -- [index_path] do
      assert index =~ "(" <> Path.relative_to(path, @root) <> ")"
    end

    for path <- notebooks -- [index_path] do
      text = File.read!(path)

      assert [[relative]] =
               Regex.scan(
                 ~r/\{:egglog_elixir, path: Path\.expand\("([^"]+)", __DIR__\)\}/,
                 text,
                 capture: :all_but_first
               )

      assert Path.expand(relative, Path.dirname(path)) == Path.dirname(@root)
      assert text =~ "{:kino,"
      refute text =~ "Egglog.Snapshot.summary"

      for [code] <- Regex.scan(~r/^```elixir\n(.*?)^```/ms, text, capture: :all_but_first) do
        refute code =~ "render: :json"
      end

      if Path.basename(path) == "getting_started.livemd" do
        assert text =~ "Egglog.EGraph.with_egraph(math_theory"
        assert text =~ "Egglog.Program.with_program(math_theory"
      else
        assert text =~ "Egglog.Program.Step.next"
        assert text =~ "defimpl Kino.Render, for: Egglog.Program.Step"
      end

      assert text =~ "render: :auto"
      assert text =~ "consolidate_protocols: false"

      for [code] <- Regex.scan(~r/^```elixir\n(.*?)^```/ms, text, capture: :all_but_first),
          String.contains?(code, "next.(step_") do
        refute code =~ "snapshot_"
        refute code =~ "phase_"
        refute code =~ "Program.with_program"
      end
    end
  end

  test "tutorial technicalities stay in the guide and library hub" do
    guide = File.read!(Path.join(@root, "README.md"))

    for term <- [
          "Egglog.Program.query!",
          "Egglog.EGraph.with_egraph",
          "Egglog.EGraph.clear_function",
          "Egglog.EGraph.push",
          "Egglog.EGraph.pop",
          "{:error, {:closed, message}}",
          "Rust",
          "dynamic-cost",
          "MIT license"
        ] do
      assert guide =~ term
    end

    for path <- Path.wildcard(Path.join(@root, "egglog-tutorial/*.livemd")) do
      text = File.read!(path)
      refute text =~ "EGGLOG_GRAPHVIZ_DOT"
      refute text =~ "Execution contract"
      refute text =~ "Source baseline, not a native handle"
    end
  end

  test "display helpers never synthesize native check outcomes" do
    for path <- Path.wildcard(Path.join(@root, "**/*.livemd")) do
      text = File.read!(path)
      refute text =~ "check_outputs"
      refute text =~ ":check_success"
      refute text =~ "def print_outputs"
    end
  end

  test "chapter experiments retain explicit sources instead of native handles across cells" do
    for path <- Path.wildcard(Path.join(@root, "egglog-tutorial/0[1-6]-*.livemd")) do
      text = File.read!(path)
      assert text =~ "step_00"
      assert text =~ "Egglog.Program.Step.new()"
      refute text =~ "Egglog.EGraph.new"
      refute text =~ "Egglog.EGraph.run(egraph"
    end
  end

  test "onboarding links resolve and never advertise hypothetical package versions" do
    paths =
      [Path.join(@root, "README.md"), Path.join(@root, "egglog-tutorial/README.md")] ++
        Path.wildcard(Path.join(@root, "**/*.livemd"))

    for path <- paths do
      text = File.read!(path)
      refute text =~ "When using the published package"

      for [_, target] <- Regex.scan(~r/\]\(([^)]+)\)/, text),
          not String.starts_with?(target, ["http:", "https:", "#"]) do
        relative = target |> String.split("#", parts: 2) |> hd()

        assert File.exists?(Path.expand(relative, Path.dirname(path))),
               "Broken link #{target} in #{path}"
      end
    end
  end
end
