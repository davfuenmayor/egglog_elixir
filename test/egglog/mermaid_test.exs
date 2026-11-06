defmodule Egglog.MermaidTest do
  use ExUnit.Case, async: false
  alias Egglog.{EGraph, Program, Snapshot}

  defp node(op, eclass, children \\ []),
    do: %{"op" => op, "eclass" => eclass, "children" => children}

  test "ordered edges preserve native child references, including repeated and cyclic arguments" do
    graph = %{
      "nodes" => %{
        "a" => node("A", "value"),
        "b" => node("B", "value"),
        "pair" => node("Pair", "value", ["b", "a"])
      },
      "class_data" => %{"value" => %{"type" => "Term", "let" => "left, right"}}
    }

    text = Snapshot.to_mermaid!(graph)
    assert text =~ ~s(subgraph c0["let left, right"])
    assert text =~ ~s(n0["A"])
    assert text =~ ~s(n1["B"])
    assert text =~ "n2 -->|0| n1"
    assert text =~ "n2 -->|1| n0"
    refute text =~ "_anchor"
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
        }
      })

    assert source =~ "n2 -->|0| c1"
    assert source =~ "n2 -->|1| c0"
    refute source =~ "n2 -->|0| c0"
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
    assert source =~ "subgraph c0"
    assert source =~ "n0 --> n0"
    refute source =~ "singleton"
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

  test "browser regression fixtures cover empty, escaped, cyclic and repeated edges" do
    graphs = [
      {"empty", %{"nodes" => %{}}},
      {"escaped",
       %{
         "nodes" => %{
           "bad" =>
             node(
               "end" <> <<34, 93, 10>> <> "%%{init:{}}%% <script>&" <> <<96, 92>> <> "λ",
               "x"
             )
         },
         "class_data" => %{"x" => %{"let" => "names: a, b" <> <<10, 34>> <> "quoted"}}
       }},
      {"subsumed",
       %{
         "nodes" => %{"a" => Map.put(node("A", "root"), "subsumed", true)},
         "class_data" => %{"root" => %{}},
         "root_eclasses" => ["root"]
       }},
      {"cycle",
       %{
         "nodes" => %{"a" => node("A", "x"), "f" => node("F", "x", ["a", "a"])},
         "class_data" => %{"x" => %{"type" => "T"}}
       }}
    ]

    for {name, graph} <- graphs do
      source = Snapshot.to_mermaid!(graph)

      if directory = System.get_env("EGGLOG_MERMAID_EXPORT_DIR") do
        File.mkdir_p!(directory)
        File.write!(Path.join(directory, "fixture-#{name}.mmd"), source)
        File.write!(Path.join(directory, "fixture-#{name}.json"), Jason.encode!(graph))
      end

      assert source =~ "flowchart TB"
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
      assert snapshot.dot_path == nil
      refute File.exists?(Path.join(dir, "unused.dot"))
      assert snapshot.mermaid =~ "let a"
      assert snapshot.mermaid =~ "let f"
      # Query-local snapshots still leave the loaded base unchanged.
      assert Program.num_tuples(program) == {:ok, 0}
    end)
  end

  test "mutable snapshots support string options, inline leaves, split primitives and caps" do
    EGraph.with_egraph(
      """
      (datatype T (Num i64) (Add T T))
      (let x (Add (Num 1) (Num 2)))
      (let y (Add (Num 3) (Num 4)))
      """,
      fn graph ->
        for opts <- [
              %{"render" => "mermaid"},
              [render: :mermaid, snapshot_inline_leaves: 2],
              [render: :mermaid, snapshot_split_primitive_outputs: true],
              [render: :mermaid, snapshot_max_functions: 1, snapshot_max_calls_per_function: 1]
            ] do
          assert {:ok, snapshot} = EGraph.snapshot(graph, opts)
          assert snapshot.format == :mermaid
          assert snapshot.mermaid =~ "flowchart TB"
          assert Snapshot.to_mermaid!(snapshot.result) == snapshot.mermaid
        end
      end
    )
  end

  test "Mermaid needs no Graphviz and does not fall back to DOT" do
    previous = System.get_env("PATH")
    System.put_env("PATH", "")

    try do
      EGraph.with_egraph("(datatype T (A)) (A)", fn graph ->
        assert {:ok, %{format: :mermaid}} = EGraph.snapshot(graph, render: :mermaid)
      end)

      Program.with_program("", fn program ->
        assert {:ok, %{format: :mermaid}} =
                 Program.snapshot(program, "(datatype T (A)) (A)", render: :mermaid)
      end)
    after
      if previous, do: System.put_env("PATH", previous), else: System.delete_env("PATH")
    end
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
