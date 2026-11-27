defmodule Egglog.Extraction do
  @moduledoc """
  Reading structured native extraction results.

  Pass `extract_format: :structured` to `Egglog.EGraph.extract/3` or
  `Egglog.Program.extract/4`. The returned map contains:

    * `:nodes` — a DAG stored as a list. Node IDs are zero-based list indices.
      Nodes are `{:call, name, child_ids}`, `{:literal, value}` or `{:var, name}`.
      Names are strings; children precede their parents in the list and retain
      native argument order.
    * `:roots` — a list of `%{root: node_id, cost: integer}` maps.
      Each cost comes directly from upstream's extractor. Best extraction has
      one root; `:variants` returns root alternatives, not an enumeration of every
      equivalent expression. No valid variants is represented by an empty list.

  Literals retain native integers, finite floats, strings and booleans. Unit is
  `nil`; non-finite floats are `:nan`, `:infinity` or `:negative_infinity`.
  DAG IDs belong only to this result, never to the live e-graph. Shared child IDs
  preserve sharing; the cost still measures the native extraction objective.

  For example, with `x` bound to `(Num 1)`:

      data = Egglog.EGraph.extract!(graph, "x", extract_format: :structured)
      [%{root: root, cost: cost}] = data.roots
      {:call, "Num", [{:literal, 1}]} = Egglog.Extraction.term(data)

  Best terms and variants work with proof-enabled handles. Both return the
  original native DAG and costs without formatting or parsing extracted terms.
  Ordinary `run/3` outputs keep their existing text-only shape.
  """

  @doc """
  Reads a root as a nested term; `index` selects a zero-based entry in `:roots`.

  Calls become `{:call, name, terms}`; literals and variables keep their tags.
  Raises if the root index is absent, including an extraction with no variants.
  This reads retained data and never executes egglog.
  """
  def term(%{nodes: nodes, roots: roots}, index \\ 0) do
    %{root: root} = Enum.fetch!(roots, index)

    nodes
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {node, id}, terms ->
      term =
        case node do
          {:call, name, children} -> {:call, name, Enum.map(children, &Map.fetch!(terms, &1))}
          leaf -> leaf
        end

      Map.put(terms, id, term)
    end)
    |> Map.fetch!(root)
  end
end
