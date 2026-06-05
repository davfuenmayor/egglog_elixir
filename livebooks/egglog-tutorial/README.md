# Egglog Tutorial Livebook Clones

These notebooks adapt the upstream egglog tutorial from <https://egraphs-good.github.io/egglog-tutorial/> to the thin `egglog_elixir` wrapper.

Open the chapters in order:

- [Equality Saturation](livebooks/egglog-tutorial/01-basics.livemd)
- [Datalog](livebooks/egglog-tutorial/02-datalog.livemd)
- [E-class analysis](livebooks/egglog-tutorial/03-analysis.livemd)
- [Scheduling](livebooks/egglog-tutorial/04-scheduling.livemd)
- [Extraction and Cost](livebooks/egglog-tutorial/05-cost-model-and-extraction.livemd)
- [Case study: LA compiler](livebooks/egglog-tutorial/06-case-study.livemd)

Each chapter is standalone and installs `egglog_elixir` from the library root using a path relative to the notebook.

## Adaptation Notes

These Livebooks are close to the cloned upstream `.egg` sources, but they are not byte-for-byte conversions.

- The egglog command blocks stay visible and in the original chapter order wherever possible.
- Each chapter uses one live `Egglog.EGraph` session, so `(push)`, `(pop)`, rules, facts, checks, and extraction operate on the same mutable native e-graph that a direct interactive egglog session would use.
- Cells that change the e-graph call the public API directly: `Egglog.EGraph.new/0`, `Egglog.EGraph.run/2`, `Egglog.EGraph.snapshot!/2`, and `Egglog.EGraph.num_tuples/1`.
- The small `Tutorial` modules are display-only glue for Livebook output, SVG rendering, and JSON-summary helpers for inspecting the current e-graph.
- Several silent `(check ...)` commands are followed by small Elixir summaries so beginners can see whether a check succeeded without reading an exception trace.
- Snapshot cells render SVG in Livebook when Graphviz is installed; otherwise they fall back to textual DOT output.

## Scope Notes

The first three chapters are ordinary egglog-language tutorials and are executable
through the thin wrapper.

Chapter 4 is executable through the scheduling material based on rulesets,
`run-schedule`, `saturate`, `repeat`, and `run`. Upstream also discusses
experimental scheduler constructs such as `let-scheduler`, `run-with`, and
`back-off`; those blocks are preserved as reference text rather than executed.

Chapter 5 is executable for ordinary extraction and constructor `:cost`
annotations. The dynamic-cost material, including `with-dynamic-cost`,
`set-cost`, and `DynamicCostModel`, depends on experimental/native extension
features and is kept as reference text.

Chapter 6 is a Rust-library case study. It covers a custom parser, AST lowering,
Rust-side extraction, custom schedulers, and custom cost models. The Livebook is
a guided map of that upstream project, not an Elixir reimplementation of those
Rust extension hooks.
