defmodule Egglog.MermaidTest do
  use ExUnit.Case, async: true
  alias Egglog.{EGraph, Program, Snapshot}

  defp node(op, eclass, children \\ []),
    do: %{"op" => op, "eclass" => eclass, "children" => children}

  test "ordered edges preserve repeated arguments within a class" do
    graph = %{
      "nodes" => %{
        "a" => node("A", "value"),
        "b" => node("B", "value"),
        "call" => node("Call", "value", ["b", "a", "a"])
      },
      "class_data" => %{"value" => %{"type" => "Term", "let" => "left, right"}}
    }

    text = Snapshot.to_mermaid!(graph)
    assert text =~ ~s(["let left, right"])
    a = id_for_label(text, "A")
    b = id_for_label(text, "B")
    call = id_for_label(text, "Call")
    assert text =~ "#{call} -->|0| #{b}"
    assert text =~ "#{call} -->|1| #{a}"
    assert text =~ "#{call} -->|2| #{a}"
    assert length(Regex.scan(~r/^  subgraph /m, text)) == 1
    assert Snapshot.to_mermaid!(Jason.encode!(graph)) == text
    assert Snapshot.to_mermaid!(%{snapshot: %{format: :json, text: Jason.encode!(graph)}}) == text
  end

  test "noncommutative argument order survives edges between different classes" do
    source =
      Snapshot.to_mermaid!(%{
        "nodes" => %{
          "a" => node("A", "left"),
          "b" => node("B", "right"),
          "concat" => node("Concat", "word", ["b", "a"])
        },
        "class_data" => %{"left" => %{"let" => "left"}, "right" => %{"let" => "right"}}
      })

    concat = id_for_label(source, "Concat")
    left = id_for_label(source, "let left")
    right = id_for_label(source, "let right")
    assert source =~ "#{concat} -->|0| #{right}"
    assert source =~ "#{concat} -->|1| #{left}"
  end

  test "independent classes are never merged by equal labels and native IDs stay out of syntax" do
    text =
      Snapshot.to_mermaid!(%{
        "nodes" => %{"weird[]id" => node("Same", "x"), "end" => node("Same", "y")}
      })

    assert length(Regex.scan(~r/^  subgraph /m, text)) == 2
    assert length(Regex.scan(~r/\["Same"\]/, text)) == 2
    refute text =~ "weird[]id"
  end

  test "labels escape syntax, HTML, directives, multiline strings and Unicode" do
    dangerous = "end\"]\n%%{init: {}}%% <script>&" <> <<96>> <> "\\λ"

    text =
      Snapshot.to_mermaid!(%{
        "nodes" => %{"a" => node(dangerous, "x")},
        "class_data" => %{"x" => %{"let" => dangerous}}
      })

    assert text =~ "#34;#93;<br/>#37;#37;"
    assert text =~ "#60;script#62;#38;#96;#92;λ"
    refute text =~ "<script>"
    refute text =~ "%%{init: {}}%%"
  end

  test "empty metadata classes add no vertices; root and subsumption metadata survive" do
    empty = Snapshot.to_mermaid!(%{"nodes" => %{}})
    refute empty =~ "\n  subgraph "
    refute empty =~ "empty["

    text =
      Snapshot.to_mermaid!(%{
        "nodes" => %{"a" => Map.put(node("A", "x"), "subsumed", true)},
        "class_data" => %{"x" => %{}, "empty" => %{}},
        "root_eclasses" => ["x"]
      })

    assert text =~ "%% subsumed n0"
    assert text =~ "stroke-width:2px"
    refute text =~ ~s("empty")
    assert text =~ ~s(subgraph c0[" "])
  end

  test "Graphviz labels and type colors omit IDs/types and preserve extra metadata" do
    text =
      Snapshot.to_mermaid!(%{
        "nodes" => %{"a" => node("A", "x"), "b" => node("B", "y"), "c" => node("C", "z")},
        "class_data" => %{
          "x" => %{"type" => "DNA", "let" => "a", "note" => "line 1\nline 2"},
          "y" => %{"type" => "DNAFormula", "let" => "claim"},
          "z" => %{"type" => "DNA"}
        }
      })

    assert text =~ "let a<br/>note line 1<br/>line 2"
    assert text =~ "style c0 fill:#ffffb3"
    assert text =~ "style c1 fill:#ffffb3"
    assert text =~ "style c2 fill:#bebada"
    refute text =~ "#124;"
    refute text =~ ":::subsumed"
  end

  test "cross-class arrows terminate at the class boundary rather than a member" do
    source =
      Snapshot.to_mermaid!(%{
        "nodes" => %{
          "a" => node("A", "value"),
          "b" => node("B", "value"),
          "f" => node("F", "outer", ["b"])
        }
      })

    assert source =~ "%% edge n2 0 n1"
    assert source =~ "n2 --> c1"
    refute source =~ "n2 --> n1"
    refute source =~ "n2 -->|0|"
  end

  test "a singleton self-loop keeps its constructor endpoint instead of targeting its parent class" do
    source = Snapshot.to_mermaid!(%{"nodes" => %{"f" => node("F", "value", ["f"])}})
    constructor = id_for_label(source, "F")
    assert source =~ "#{constructor} --> #{constructor}"
  end

  test "malformed JSON, schema and dangling children return errors instead of invented equalities" do
    for graph <- [
          "not JSON",
          "[]",
          %{"nodes" => []},
          %{"nodes" => %{}, "class_data" => nil},
          %{"nodes" => %{"a" => node("A", "x", ["missing"])}},
          %{"nodes" => %{"a" => %{}}},
          %{"nodes" => %{"a" => node(<<255>>, "x")}},
          %{"nodes" => %{}, "root_eclasses" => false},
          %{"nodes" => %{}, "class_data" => %{"x" => %{"let" => []}}}
        ] do
      assert {:error, {:invalid_snapshot, _}} = Snapshot.to_mermaid(graph)
      assert_raise RuntimeError, fn -> Snapshot.to_mermaid!(graph) end
    end
  end

  @tag :tmp_dir
  test "Program requests native JSON, preserves metadata, and writes Mermaid and JSON", %{
    tmp_dir: dir
  } do
    source = """
    (datatype X (A) (B) (F X))
    (let a (A))
    (let f (F a))
    (union a (B))
    (check (= (F (B)) f))
    """

    Program.with_program("", fn program ->
      snapshot =
        Program.snapshot!(program, source,
          render: :mermaid,
          path: Path.join(dir, "primary.mmd"),
          mermaid_path: Path.join(dir, "graph.mmd"),
          json_path: Path.join(dir, "native.json"),
          dot_path: Path.join(dir, "unused.dot")
        )

      assert snapshot.format == :mermaid
      assert snapshot.text == snapshot.mermaid
      assert snapshot.result.snapshot.format == :json
      assert snapshot.result.status == :ok
      assert snapshot.omitted == snapshot.result.snapshot.omitted
      assert snapshot.stats.snapshot_nodes == map_size(Snapshot.nodes(snapshot))
      assert Snapshot.to_mermaid!(snapshot) == snapshot.mermaid
      assert File.read!(snapshot.path) == snapshot.mermaid
      assert File.read!(snapshot.mermaid_path) == snapshot.mermaid
      assert File.read!(snapshot.json_path) == snapshot.json
      assert File.read!(snapshot.dot_path) == snapshot.dot
      assert snapshot.mermaid =~ "let a"
      assert snapshot.mermaid =~ "let f"
      # Query-local snapshots still leave the loaded base unchanged.
      assert Program.num_tuples(program) == {:ok, 0}
    end)
  end

  test "Mermaid reports a partial graph when a serialization cap omits functions" do
    EGraph.with_egraph(
      "(datatype T (A) (B)) (A) (B)",
      fn graph ->
        full = EGraph.snapshot!(graph, render: :mermaid)

        partial =
          EGraph.snapshot!(graph, %{"render" => "mermaid", "snapshot_max_functions" => 1})

        assert full.complete
        refute partial.complete
        assert partial.format == :mermaid
        assert map_size(Snapshot.nodes(partial)) < map_size(Snapshot.nodes(full))
      end
    )
  end

  defp id_for_label(source, label) do
    [_, id] = Regex.run(~r/^ *(?:subgraph )?(\w+)\["#{Regex.escape(label)}"\]/m, source)
    id
  end

  @tag :tmp_dir
  test "artifact IO errors keep the established non-bang/bang contract", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "file"), "")

    EGraph.with_egraph("", fn graph ->
      path = Path.join([dir, "file", "graph.mmd"])

      assert {:error, {:snapshot_io, ^path, _}} =
               EGraph.snapshot(graph, render: :mermaid, mermaid_path: path)

      assert_raise RuntimeError, fn ->
        EGraph.snapshot!(graph, render: :mermaid, mermaid_path: path)
      end
    end)
  end
end
