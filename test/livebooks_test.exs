defmodule Egglog.LivebooksTest do
  use ExUnit.Case, async: true

  @root Path.expand("../livebooks", __DIR__)
  @version Mix.Project.config()[:version]

  test "the navigation-only index links to every notebook" do
    index_path = Path.join(@root, "index.livemd")
    index = File.read!(index_path)
    assert code_cells(index) == []

    targets = for [_, target] <- links(index), do: target

    for path <- notebooks() do
      assert Path.relative_to(path, @root) in targets, "Index is missing #{path}"
    end
  end

  test "notebook setup installs the current release from Hex" do
    for path <- notebooks() do
      assert [setup | _] = code_cells(File.read!(path))

      expressions =
        case Code.string_to_quoted!(setup, file: path) do
          {:__block__, _, expressions} -> expressions
          expression -> [expression]
        end

      installations =
        for {{:., _, [{:__aliases__, _, [:Mix]}, :install]}, _, [deps | _]} <- expressions,
            do: deps

      assert [deps] = installations, "Expected one Mix.install call in #{path}"
      assert Keyword.get_values(deps, :egglog_elixir) == [@version], "Wrong release in #{path}"
      assert Keyword.has_key?(deps, :kino), "Missing Kino dependency in #{path}"
    end
  end

  test "relative onboarding links resolve" do
    paths =
      [Path.join(@root, "README.md"), Path.join(@root, "egglog-tutorial/README.md")] ++
        Path.wildcard(Path.join(@root, "**/*.livemd"))

    for path <- paths,
        [_, target] <- links(File.read!(path)),
        not String.starts_with?(target, ["http:", "https:", "#"]) do
      relative = target |> String.split("#", parts: 2) |> hd()

      assert File.exists?(Path.expand(relative, Path.dirname(path))),
             "Broken link #{target} in #{path}"
    end
  end

  defp notebooks do
    Path.wildcard(Path.join(@root, "**/*.livemd")) -- [Path.join(@root, "index.livemd")]
  end

  defp links(text), do: Regex.scan(~r/\]\(([^)]+)\)/, text)

  defp code_cells(text) do
    Regex.scan(~r/^```elixir\r?\n(.*?)^```/ms, text, capture: :all_but_first)
    |> List.flatten()
  end
end
