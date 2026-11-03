defmodule Egglog.Mermaid do
  @moduledoc false

  # JSON child references name e-nodes, but arguments denote their e-classes.
  def render(%{"nodes" => nodes} = graph) when is_map(nodes) do
    classes = Map.get(graph, "class_data", %{})
    roots = Map.get(graph, "root_eclasses", [])

    with :ok <- validate(nodes, classes, roots) do
      class_ids =
        (Map.keys(classes) ++ Enum.map(nodes, fn {_, node} -> node["eclass"] end) ++ roots)
        |> Enum.uniq()
        |> Enum.sort()

      class_names = class_ids |> Enum.with_index() |> Map.new(fn {id, i} -> {id, "c#{i}"} end)

      node_names =
        nodes
        |> Map.keys()
        |> Enum.sort()
        |> Enum.with_index()
        |> Map.new(fn {id, i} -> {id, "n#{i}"} end)

      members = Enum.group_by(nodes, fn {_, node} -> node["eclass"] end)

      groups =
        Enum.map(class_ids, fn id ->
          name = class_names[id]
          metadata = Map.get(classes, id, %{})

          title =
            Enum.join(
              Enum.reject([id, metadata["type"], alias_label(metadata["let"])], &is_nil/1),
              " | "
            )

          [
            "  subgraph #{name}[\"#{escape(title)}\"]\n",
            "    #{name}_anchor((\"=\"))\n",
            Enum.map(Enum.sort(Map.get(members, id, [])), fn {node_id, node} ->
              suffix = if node["subsumed"] == true, do: ":::subsumed", else: ""
              "    #{node_names[node_id]}[\"#{escape(node["op"])}\"]#{suffix}\n"
            end),
            "  end\n",
            if(id in roots, do: "  style #{name} stroke-width:3px\n", else: [])
          ]
        end)

      edges =
        Enum.map(Enum.sort(nodes), fn {id, node} ->
          node["children"]
          |> Enum.with_index()
          |> Enum.map(fn {child, position} ->
            target = class_names[nodes[child]["eclass"]]
            "  #{node_names[id]} -->|#{position}| #{target}_anchor\n"
          end)
        end)

      empty = if class_ids == [], do: "  empty[\"Empty e-graph\"]\n", else: []

      {:ok,
       IO.iodata_to_binary([
         "flowchart TB\n",
         "  %% Each subgraph is an e-class; = anchors are argument targets, not constructors.\n",
         groups,
         edges,
         empty,
         "  classDef subsumed stroke-dasharray: 4 3\n"
       ])}
    end
  end

  def render(_), do: invalid("expected an object containing a nodes map")

  defp validate(nodes, classes, roots) do
    cond do
      not is_map(classes) ->
        invalid("class_data must be a map")

      not (is_list(roots) and Enum.all?(roots, &valid_text?/1)) ->
        invalid("root_eclasses must be a list of IDs")

      not Enum.all?(classes, fn {id, data} ->
        valid_text?(id) and is_map(data) and
          (is_nil(data["type"]) or valid_text?(data["type"])) and
            (is_nil(data["let"]) or valid_text?(data["let"]))
      end) ->
        invalid("class metadata must contain string IDs and optional type/let strings")

      not Enum.all?(nodes, fn {id, node} ->
        valid_text?(id) and is_map(node) and valid_text?(node["op"]) and
          valid_text?(node["eclass"]) and is_list(node["children"]) and
            Enum.all?(node["children"], &valid_text?/1)
      end) ->
        invalid("nodes require string IDs, op/eclass strings, and a children list")

      true ->
        case Enum.find_value(Enum.sort(nodes), fn {id, node} ->
               case Enum.find(node["children"], &(not Map.has_key?(nodes, &1))) do
                 nil -> nil
                 missing -> "#{id} references missing child #{missing}"
               end
             end) do
          nil -> :ok
          message -> invalid(message)
        end
    end
  end

  defp valid_text?(value), do: is_binary(value) and String.valid?(value)

  defp alias_label(nil), do: nil
  defp alias_label(""), do: nil
  defp alias_label(name), do: "let " <> name

  # Generated IDs never contain native/user text. Entity-encode punctuation
  # so quotes, HTML, directives, Markdown, newlines and delimiters stay data.
  defp escape(text) do
    for <<codepoint::utf8 <- text>>, into: "" do
      if codepoint in ?a..?z or codepoint in ?A..?Z or codepoint in ?0..?9 or
           codepoint in [?\s, ?_, ?-, ?., ?,, ?:, ?/] or codepoint > 159 do
        <<codepoint::utf8>>
      else
        "##{codepoint};"
      end
    end
  end

  defp invalid(message), do: {:error, {:invalid_snapshot, message}}
end
