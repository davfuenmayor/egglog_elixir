defmodule Egglog.LivebooksTest do
  use ExUnit.Case, async: true
  @root Path.expand("../livebooks", __DIR__)
  @fence String.duplicate(<<96>>, 3)

  test "executable notebooks install this checkout; reference-only chapter has no runtime" do
    notebooks = Path.wildcard(Path.join(@root, "**/*.livemd"))
    assert notebooks != []

    for path <- notebooks do
      text = File.read!(path)

      if Path.basename(path) == "06-case-study.livemd" do
        assert text =~ "**Status: reference only.**"
        refute text =~ @fence <> "elixir"
        refute text =~ "Mix.install"
      else
        assert [[relative]] =
                 Regex.scan(
                   ~r/\{:egglog_elixir, path: Path\.expand\("([^"]+)", __DIR__\)\}/,
                   text, capture: :all_but_first)

        assert Path.expand(relative, Path.dirname(path)) == Path.dirname(@root)
        assert text =~ "{:kino,"
        refute String.replace(text, @fence, "~~~") =~ ~r/^~~~(?:python|rust)\s*$/m
      end
    end
  end

  test "Getting Started demonstrates queries, explicit state, rollback and closed handles" do
    text = File.read!(Path.join(@root, "getting_started.livemd"))

    for call <- [
          "Egglog.Program.query!",
          "Egglog.Program.with_program",
          "Egglog.EGraph.with_egraph",
          "Egglog.EGraph.clear_function",
          "Egglog.EGraph.push",
          "Egglog.EGraph.pop",
          "{:error, {:closed, _}}"
        ] do
      assert text =~ call
    end

    refute text =~ "Enum.each([math, cc, reach, guarded]"
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
    for path <- Path.wildcard(Path.join(@root, "egglog-tutorial/0[1-5]-*.livemd")) do
      text = File.read!(path)
      assert text =~ "phase_00"
      assert text =~ "Egglog.Program.with_program"
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
