# Dev-only: export native DOT and JSON from the same live graph, without mutation
# between serializations. The browser checker compares both labelled graphs.
root = Path.expand("..", __DIR__)
Mix.install([{:egglog_elixir, path: root}, {:kino, "~> 0.19.0"}])
directory = Path.expand(List.first(System.argv()) || Path.join(root, "tmp/graph-parity"))
File.mkdir_p!(directory)
assets = Path.join(directory, "kino-assets")
File.mkdir_p!(assets)

:ok =
  :erl_tar.extract(
    String.to_charlist(Kino.Mermaid.__assets_info__().archive_path),
    [:compressed, {:cwd, String.to_charlist(assets)}]
  )

dna = """
(datatype DNA (A) (G) (C) (T) (Concat DNA DNA) (RC DNA))
(datatype Claim (SameDNA DNA DNA))
(rewrite (RC (A)) (T))
(rewrite (RC (G)) (C))
(rewrite (RC (Concat x y)) (Concat (RC y) (RC x)))
(let ag (Concat (A) (G)))
(let rcag (RC ag))
(let ct (Concat (C) (T)))
(let claim (SameDNA rcag ct))
"""

boolean = """
(datatype Concept (Students) (Researchers) (And Concept Concept) (Or Concept Concept))
(let s (Students))
(let r (Researchers))
(let sr (And s r))
(let rs (And r s))
(let repeated (And s s))
"""

arithmetic = """
(datatype Expr (Num i64) (Add Expr Expr))
(let value (Add (Num 1) (Num 2)))
"""

# These inputs exercise native serializer behavior; notebook lesson sources stay
# in their authoritative Livebooks rather than being copied into test fixtures.
cases = [
  {"empty", "", []},
  {"dna-before", dna, []},
  {"dna-one-round", dna <> "(run 1)", []},
  {"dna-two-rounds", dna <> "(run 2)", []},
  {"boolean-before", boolean, []},
  {"boolean-merged", boolean <> "(union sr rs) (union repeated s)", []},
  {"repeated-and-self-cycle", "(datatype T (A) (F T T)) (let a (A)) (let f (F a a)) (union a f)",
   []},
  {"primitives", arithmetic, []},
  {"inlined", arithmetic, [snapshot_inline_leaves: 2]},
  {"split-primitives", arithmetic, [snapshot_split_primitive_outputs: true]},
  {"capped", dna, [snapshot_max_functions: 2, snapshot_max_calls_per_function: 1]},
  {"escaped",
   "(datatype Label (Text String)) (let literal (Text " <>
     Jason.encode!("end\"]\n%%{init:{}}%% <script>&`\\λ") <> "))", []}
]

for {name, source, opts} <- cases do
  Egglog.EGraph.with_egraph(source, fn graph ->
    json = Egglog.EGraph.snapshot!(graph, Keyword.put(opts, :render, :json))
    dot = Egglog.EGraph.snapshot!(graph, Keyword.put(opts, :render, :dot))
    File.write!(Path.join(directory, name <> ".json"), json.json)
    File.write!(Path.join(directory, name <> ".dot"), dot.dot)
    File.write!(Path.join(directory, name <> ".mmd"), Egglog.Snapshot.to_mermaid!(json))
    IO.puts("EXPORTED #{name}: #{json.stats.snapshot_nodes} nodes")
  end)
end

IO.puts("Browser check: node scripts/check_mermaid_browser.cjs #{assets} #{directory}")
