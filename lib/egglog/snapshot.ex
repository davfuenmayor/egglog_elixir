defmodule Egglog.Snapshot do
  @moduledoc """
  Helpers for egglog JSON snapshots.

  The wrapper asks native egglog to serialize snapshots. This module only
  decodes that JSON, exports Mermaid flowcharts, and computes small summaries
  that are convenient in tests, notebooks, and debugging sessions.
  """

  @doc """
  Decodes an egglog JSON snapshot.

  Accepts a raw JSON string, a snapshot map returned by `Egglog.snapshot/3`, or
  a run result containing a native `:snapshot`.
  """
  def decode(json) when is_binary(json), do: Jason.decode(json)

  def decode(%{"nodes" => _nodes} = decoded), do: {:ok, decoded}
  def decode(%{json: json}) when is_binary(json), do: decode(json)
  def decode(%{text: json, format: :json}) when is_binary(json), do: decode(json)
  def decode(%{snapshot: snapshot}) when is_map(snapshot), do: decode(snapshot)
  def decode(_snapshot), do: {:error, :not_a_json_snapshot}

  @doc """
  Bang variant of `decode/1`.
  """
  def decode!(snapshot) do
    case decode(snapshot) do
      {:ok, decoded} -> decoded
      {:error, reason} -> raise "failed to decode egglog JSON snapshot: #{inspect(reason)}"
    end
  end

  @doc """
  Converts native snapshot JSON to Mermaid flowchart source without rerunning
  egglog or invoking Graphviz. Accepts the same inputs as decode/1.

  Follows DOT's visible edge contract: cross-class arrows terminate on the
  outer equality-class box, while internal edges retain their member-node
  endpoint. Original child references remain in source comments. Every class
  uses the same subgraph representation; white inner boxes are constructors.
  Dashed class boxes retain native type colors and metadata titles.

  Multi-argument edges retain numeric argument indices; unary zero labels are
  omitted. Kino's bundled Mermaid does not expose DOT source ports or reliable
  endpoint-label placement, so label positions and routing remain automatic.
  Class spacing is left to Mermaid and may be wider than Graphviz's layout.
  Native IDs/metadata and subsumed flags remain in safe source comments; roots
  have thicker borders. Empty metadata-only classes add no vertices.

  Layout differs from Graphviz. Native snapshot limits/leaf inlining apply
  before conversion; inspect omission metadata for capped snapshots.

  Invalid JSON/schema or dangling children return an error. IDs are generated
  deterministically for a given snapshot, and labels are escaped.
  """
  def to_mermaid(snapshot) do
    case decode(snapshot) do
      {:ok, graph} -> Egglog.Mermaid.render(graph)
      {:error, reason} -> {:error, {:invalid_snapshot, reason}}
    end
  end

  @doc "Bang variant of to_mermaid/1."
  def to_mermaid!(snapshot) do
    snapshot
    |> to_mermaid()
    |> Egglog.Common.bang("failed to convert snapshot to Mermaid")
  end

  @doc """
  Returns the serialized node map from a decoded or raw JSON snapshot.
  """
  def nodes(snapshot), do: decode!(snapshot) |> Map.get("nodes", %{})

  @doc """
  Returns the serialized e-class metadata map from a decoded or raw JSON snapshot.
  """
  def classes(snapshot), do: decode!(snapshot) |> Map.get("class_data", %{})

  @doc """
  Counts serialized e-nodes by operator name.
  """
  def operator_counts(snapshot) do
    snapshot
    |> nodes()
    |> count_operators()
  end

  @doc """
  Returns a compact summary of an egglog JSON snapshot.

  The summary is deliberately plain data so it can be displayed directly in
  IEx, tests, or Livebook.
  """
  def summary(snapshot) do
    decoded = decode!(snapshot)
    nodes = Map.get(decoded, "nodes", %{})
    classes = Map.get(decoded, "class_data", %{})
    omitted = omitted(snapshot)

    %{
      nodes: map_size(nodes),
      classes: map_size(classes),
      operators: count_operators(nodes),
      omitted: if(omitted in [nil, ""], do: nil, else: omitted)
    }
  end

  defp count_operators(nodes) do
    nodes
    |> Map.values()
    |> Enum.reduce(%{}, fn node, counts ->
      Map.update(counts, Map.get(node, "op", "?"), 1, &(&1 + 1))
    end)
  end

  defp omitted(%{omitted: omitted}), do: omitted
  defp omitted(%{snapshot: snapshot}) when is_map(snapshot), do: omitted(snapshot)
  defp omitted(_snapshot), do: nil
end
