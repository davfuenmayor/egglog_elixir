# Loaded only by the dev notebook checkers when EGGLOG_GRAPH_PARITY_DIR is set.
defmodule EgglogGraphParityCapture do
  def program_snapshot!(program, input, opts \\ []) do
    record(Egglog.Program.snapshot!(program, input, opts))
  end

  def graph_snapshot!(graph, opts \\ []) do
    record(Egglog.EGraph.snapshot!(graph, opts))
  end

  defp record(%{format: :mermaid, json: json, mermaid: source} = snapshot) do
    directory = System.fetch_env!("EGGLOG_GRAPH_PARITY_DIR")
    File.mkdir_p!(directory)
    id = :crypto.hash(:sha256, json) |> Base.encode16(case: :lower)
    File.write!(Path.join(directory, id <> ".json"), json)
    File.write!(Path.join(directory, id <> ".mmd"), source)
    notebook = Process.get(:egglog_parity_notebook, "unknown")
    seen = Process.get(:egglog_parity_seen, MapSet.new())

    unless MapSet.member?(seen, {id, notebook}) do
      File.write!(
        Path.join(directory, "sources.ndjson"),
        Jason.encode!(%{name: id, notebook: notebook}) <> "\n",
        [:append]
      )

      Process.put(:egglog_parity_seen, MapSet.put(seen, {id, notebook}))
    end

    snapshot
  end

  defp record(snapshot), do: snapshot

  def instrument(source) do
    source
    |> String.replace("Egglog.Program.snapshot!(", "EgglogGraphParityCapture.program_snapshot!(")
    |> String.replace("Egglog.EGraph.snapshot!(", "EgglogGraphParityCapture.graph_snapshot!(")
  end
end

if directory = System.get_env("EGGLOG_GRAPH_PARITY_DIR") do
  assets = Path.join(directory, "kino-assets")
  File.mkdir_p!(assets)

  :ok =
    :erl_tar.extract(
      String.to_charlist(Kino.Mermaid.__assets_info__().archive_path),
      [:compressed, {:cwd, String.to_charlist(assets)}]
    )
end
