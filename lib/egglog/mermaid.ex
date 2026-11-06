defmodule Egglog.Mermaid do
  @moduledoc false

  @palette ~w(#8dd3c7 #ffffb3 #bebada #fb8072 #80b1d3 #fdb462 #b3de69 #fccde5 #d9d9d9 #bc80bd #ccebc5 #ffed6f)
  @config %{
    theme: "base",
    fontFamily: "Helvetica",
    themeVariables: %{fontSize: "9px", lineColor: "#000000", primaryTextColor: "#000000"},
    flowchart: %{nodeSpacing: 4, rankSpacing: 26, padding: 3, curve: "basis"}
  }
  @node_style "fill:#ffffff,stroke:#000000,color:#000000,stroke-width:1px,rx:8,ry:8,font-size:14px"

  def render(%{"nodes" => nodes} = graph) when is_map(nodes) do
    metadata = Map.get(graph, "class_data", %{})
    roots = Map.get(graph, "root_eclasses", [])

    with :ok <- validate(nodes, metadata, roots) do
      classes =
        nodes
        |> Enum.group_by(fn {_, node} -> node["eclass"] end)
        |> Enum.sort_by(fn {id, _} -> {get_in(metadata, [id, "type"]), id} end)

      context = %{
        nodes: nodes,
        node_ids: names(Enum.sort(Map.keys(nodes)), "n"),
        class_ids: names(Enum.map(classes, &elem(&1, 0)), "c"),
        metadata: metadata,
        roots: MapSet.new(roots),
        colors: type_colors(classes, metadata)
      }

      {:ok,
       IO.iodata_to_binary([
         "%%{init: #{Jason.encode!(@config)}}%%\nflowchart TB\n",
         Enum.map(classes, &render_class(&1, context)),
         Enum.map(Enum.sort(nodes), &render_edges(&1, context)),
         "  classDef enode #{@node_style}\n"
       ])}
    end
  end

  def render(_), do: invalid("expected an object containing a nodes map")

  defp render_class({id, members}, context) do
    name = context.class_ids[id]
    data = Map.get(context.metadata, id, %{})

    title =
      data
      |> Map.delete("type")
      |> Enum.reject(fn {_, value} -> is_nil(value) end)
      |> Enum.sort()
      |> Enum.map_join("\n", fn {key, value} -> key <> " " <> value end)

    border = if MapSet.member?(context.roots, id), do: 2, else: 1

    [
      "  %% class #{name} #{comment(%{"id" => id, "data" => data})}\n",
      "  subgraph #{name}[\"#{escape(if(title == "", do: " ", else: title))}\"]\n",
      Enum.map(Enum.sort(members), fn {id, node} ->
        nid = context.node_ids[id]

        [
          "    %% node #{nid} #{comment(id)}\n",
          if(node["subsumed"] == true, do: "    %% subsumed #{nid}\n", else: []),
          "    #{nid}[\"#{escape(node["op"])}\"]:::enode\n"
        ]
      end),
      "  end\n",
      "  style #{name} fill:#{context.colors[data["type"]]},stroke:#000000,stroke-width:#{border}px,stroke-dasharray:5 3,rx:8,ry:8,font-size:9px\n"
    ]
  end

  defp render_edges({id, node}, context) do
    source = context.node_ids[id]

    node["children"]
    |> Enum.with_index()
    |> Enum.map(fn {child, position} ->
      child_class = context.nodes[child]["eclass"]
      # DOT lhead clips incoming arrows at the class boundary. For internal
      # edges DOT ignores lhead, retaining the exact member/self-loop target.
      target =
        if child_class == node["eclass"],
          do: context.node_ids[child],
          else: context.class_ids[child_class]

      label = if length(node["children"]) == 1, do: "", else: "|#{position}|"

      [
        "  %% edge #{source} #{position} #{context.node_ids[child]}\n",
        "  #{source} -->#{label} #{target}\n"
      ]
    end)
  end

  defp names(ids, prefix),
    do: ids |> Enum.with_index() |> Map.new(fn {id, i} -> {id, "#{prefix}#{i}"} end)

  defp type_colors(classes, metadata) do
    classes
    |> Enum.map(fn {id, _} -> get_in(metadata, [id, "type"]) end)
    |> Enum.uniq()
    |> Enum.with_index()
    |> Map.new(fn {type, index} ->
      # Match the pinned native exporter's set312 indexing, including its wrap.
      number = rem(index + 2, 12)
      {type, if(number == 0, do: "#000000", else: Enum.at(@palette, number - 1))}
    end)
  end

  defp validate(nodes, classes, roots) do
    cond do
      not is_map(classes) ->
        invalid("class_data must be a map")

      not (is_list(roots) and Enum.all?(roots, &valid_text?/1)) ->
        invalid("root_eclasses must be a list of IDs")

      not Enum.all?(classes, fn {id, data} ->
        valid_text?(id) and is_map(data) and
            Enum.all?(data, fn {key, value} ->
              valid_text?(key) and (is_nil(value) or valid_text?(value))
            end)
      end) ->
        invalid("class metadata must contain string IDs, keys and optional string values")

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

  # User text must not enter Mermaid's global directive scanner, even in comments.
  defp comment(data), do: data |> Jason.encode!() |> Base.url_encode64(padding: false)

  defp escape(text) do
    # Match Graphviz's display of doubled backslashes in native string labels.
    for <<c::utf8 <- String.replace(text, "\\\\", "\\")>>, into: "" do
      case c do
        ?\n ->
          "<br/>"

        c
        when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or
               c in [?\s, ?_, ?-, ?., ?,, ?:, ?/] or c > 159 ->
          <<c::utf8>>

        c ->
          "##{c};"
      end
    end
  end

  defp invalid(message), do: {:error, {:invalid_snapshot, message}}
end
