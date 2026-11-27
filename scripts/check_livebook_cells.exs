# Execute notebooks twice, replay cells and revisit earlier steps.
root = Path.expand("..", __DIR__)
options = System.argv()
unless options -- ["--hex", "--no-dot"] == [], do: raise("usage: [--hex] [--no-dot]")
hex? = "--hex" in options
no_dot? = "--no-dot" in options

if hex? do
  for variable <-
        ~w(EGGLOG_ELIXIR_BUNDLE EGGLOG_BUILD EGGLOG_RELEASE_BASE_URL RUSTLER_PRECOMPILED_FORCE_BUILD_ALL),
      do: System.delete_env(variable)
else
  Mix.install([{:egglog_elixir, path: root}, {:kino, "~> 0.19.0"}], consolidate_protocols: false)
end

if no_dot? do
  System.put_env("PATH", "")
  System.delete_env("EGGLOG_GRAPHVIZ_DOT")
  System.delete_env("GRAPHVIZ_DOT")
end

for path <- Path.wildcard(Path.join(root, "livebooks/**/*.livemd")) do
  # Livebook explicitly marks illustrative Elixir fences as Markdown.
  text =
    Regex.replace(
      ~r/<!-- livebook:\{"force_markdown":true\} -->\s*```[^\n]*\n.*?^```/ms,
      path |> File.read!() |> String.replace("\r\n", "\n"),
      ""
    )

  cells =
    Regex.scan(~r/^```elixir\n(.*?)^```/ms, text, capture: :all_but_first)
    |> List.flatten()

  if cells == [], do: IO.puts("INDEX #{Path.relative_to(path, root)}: navigation only")

  executable =
    if hex? do
      cells
    else
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
    end

  evaluate = fn source, {binding, env} ->
    {value, binding, env} =
      Code.eval_quoted_with_env(Code.string_to_quoted!(source), binding, env)

    if is_struct(value, Egglog.Program.Step) and value.snapshot != nil do
      if no_dot?, do: :mermaid = value.snapshot.format
      %{type: :grid, outputs: outputs} = Kino.Render.to_livebook(value)

      if value.snapshot.format in [:svg, :mermaid] do
        true = Enum.any?(outputs, &match?(%{type: :js}, &1))
      end
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

    executable |> Enum.drop(1) |> Enum.take(2) |> Enum.reduce(state, evaluate)

    IO.puts(
      "PASS #{Path.relative_to(path, root)}: #{length(cells)} cells; pass #{pass}, consecutive reruns and earlier-step revisits"
    )
  end
end
