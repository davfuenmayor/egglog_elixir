defmodule Egglog.LivebooksTest do
  use ExUnit.Case, async: true

  @root Path.expand("../livebooks", __DIR__)

  test "each notebook installs this wrapper from its correct relative directory" do
    notebooks = Path.wildcard(Path.join(@root, "**/*.livemd"))
    assert notebooks != []

    for path <- notebooks do
      text = File.read!(path)

      assert [[relative]] =
               Regex.scan(
                 ~r/\{:egglog_elixir, path: Path\.expand\("([^"]+)", __DIR__\)\}/,
                 text,
                 capture: :all_but_first
               )

      assert Path.expand(relative, Path.dirname(path)) == Path.dirname(@root)
      assert text =~ "{:kino,"
      refute text =~ ~r/^```(?:python|rust)\s*$/m
    end
  end

  test "Getting Started demonstrates native queries and scoped cleanup" do
    text = File.read!(Path.join(@root, "getting_started.livemd"))
    assert text =~ "Egglog.Program.query!"
    assert text =~ "Egglog.Program.with_program"
    assert text =~ "Egglog.EGraph.with_egraph"
    assert text =~ "Egglog.EGraph.clear_function"
    assert text =~ "Egglog.Program.close"
    assert text =~ "Egglog.EGraph.close"
  end

  test "notebook display helpers never synthesize native check results" do
    for path <- Path.wildcard(Path.join(@root, "**/*.livemd")) do
      text = File.read!(path)
      refute text =~ "check_outputs"
      refute text =~ ":check_success"
      refute text =~ "def print_outputs"
    end
  end
end
