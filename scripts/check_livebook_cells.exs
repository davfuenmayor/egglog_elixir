# Fast checks; check_livebooks.exs additionally uses Livebook's real runtime.
root = Path.expand("..", __DIR__)
unless System.argv() in [[], ["--no-dot"]], do: raise("usage: [--no-dot]")
Mix.install([{:egglog_elixir, path: root}, {:kino, "~> 0.19.0"}], consolidate_protocols: false)

if System.get_env("EGGLOG_GRAPH_PARITY_DIR"),
  do: Code.require_file(Path.join(__DIR__, "graph_parity_capture.exs"))

# Extract the actual installed Kino assets, not a different Mermaid npm version.
if directory = System.get_env("EGGLOG_MERMAID_EXPORT_DIR") do
  assets = Path.join(directory, "kino-assets")
  File.mkdir_p!(assets)
  archive = Kino.Mermaid.__assets_info__().archive_path

  :ok =
    :erl_tar.extract(
      String.to_charlist(archive),
      [:compressed, {:cwd, String.to_charlist(assets)}]
    )
end

if System.argv() == ["--no-dot"] do
  System.put_env("PATH", "")
  System.delete_env("EGGLOG_GRAPHVIZ_DOT")
  System.delete_env("GRAPHVIZ_DOT")
end

# Optional corpus capture: record exactly the source passed to Kino, so its
# browser-side renderer can be tested rather than assuming a Kino object rendered.
defmodule EgglogMermaidCapture do
  def new(source) do
    if directory = System.get_env("EGGLOG_MERMAID_EXPORT_DIR") do
      File.mkdir_p!(directory)
      File.write!(Path.join(directory, "#{System.unique_integer([:positive])}.mmd"), source)
    end

    Kino.Mermaid.new(source)
  end
end

for path <- Path.wildcard(Path.join(root, "livebooks/**/*.livemd")) do
  Process.put(:egglog_parity_notebook, Path.relative_to(path, root))
  # Livebook explicitly marks illustrative Elixir fences as Markdown.
  text =
    Regex.replace(
      ~r/<!-- livebook:\{"force_markdown":true\} -->\s*```[^\n]*\n.*?^```/ms,
      File.read!(path),
      ""
    )

  cells =
    Regex.scan(~r/^```elixir\n(.*?)^```/ms, text, capture: :all_but_first)
    |> List.flatten()

  Enum.each(cells, &Code.string_to_quoted!/1)
  if cells == [], do: IO.puts("INDEX #{Path.relative_to(path, root)}: navigation only")

  executable =
    Enum.map(cells, fn source ->
      statements =
        case Code.string_to_quoted!(source) do
          {:__block__, _, statements} -> statements
          statement -> [statement]
        end

      # Mix.install already ran above; retain helpers now defined in the setup cell.
      statements =
        Enum.reject(statements, fn
          {{:., _, [{:__aliases__, _, [:Mix]}, :install]}, _, _} -> true
          _ -> false
        end)

      Macro.to_string({:__block__, [], statements})
    end)
    |> Enum.map(&String.replace(&1, "Kino.Mermaid.new(", "EgglogMermaidCapture.new("))

  executable =
    if System.get_env("EGGLOG_GRAPH_PARITY_DIR"),
      do: Enum.map(executable, &EgglogGraphParityCapture.instrument/1),
      else: executable

  evaluate = fn source, {binding, env} ->
    {value, binding, env} =
      Code.eval_quoted_with_env(Code.string_to_quoted!(source), binding, env)

    if is_struct(value, Egglog.Program.Step) and value.snapshot != nil do
      %{type: :grid, outputs: outputs} = Kino.Render.to_livebook(value)
      true = outputs != []
    end

    {binding, env}
  end

  for pass <- 1..2, executable != [] do
    initial = {[], Code.env_for_eval(file: path)}

    state =
      Enum.reduce(executable, initial, fn source, state ->
        state = evaluate.(source, state)
        evaluate.(source, state)
      end)

    # Return to declarations, negative checks, and views after later steps.
    early =
      Enum.filter(executable, &String.contains?(&1, "next.(step_"))
      |> Enum.take(3)

    negative = Enum.filter(executable, &String.contains?(&1, "fail (check")) |> Enum.take(1)
    view = Enum.filter(executable, &String.contains?(&1, "next.(step_")) |> Enum.take(1)
    Enum.reduce(Enum.uniq(early ++ negative ++ view), state, evaluate)

    if Path.basename(path) == "getting_started.livemd" do
      {binding, _env} = state
      theory = Keyword.fetch!(binding, :math_theory)

      edited =
        String.replace(theory, "(rewrite (Mul (Num a) (Num b))\n         (Num (* a b)))", "")

      true = edited != theory

      input = """
      (let expected (Num 6))
      (let goal (Mul (Num 2) (Num 3)))
      (run 2)
      """

      Egglog.Program.with_program(theory, fn original ->
        true = Egglog.Program.check?(original, input, "(= goal expected)")

        Egglog.Program.with_program(edited, fn replacement ->
          false = Egglog.Program.check?(replacement, input, "(= goal expected)")
        end)

        # Editing source text did not mutate the already-loaded base.
        true = Egglog.Program.check?(original, input, "(= goal expected)")
      end)

      IO.puts("PASS theory-edit/reload contract")
    end

    IO.puts(
      "PASS #{Path.relative_to(path, root)}: #{length(cells)} cells; pass #{pass}, consecutive reruns and earlier-step revisits"
    )
  end
end
