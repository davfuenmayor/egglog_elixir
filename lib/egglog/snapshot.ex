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

  E-classes are subgraphs containing constructor nodes and a circular =
  argument anchor. Zero-based edge labels preserve argument order. Edges
  target the child's class anchor, not a particular representative. Native
  let aliases and types appear in class titles; subsumed nodes are dashed.

  Pass the result to Kino.Mermaid.new/1 (Kino is an optional caller dependency).
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
