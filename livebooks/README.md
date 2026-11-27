# Livebooks

> **⚠️ Warning:** Install Graphviz (`dot` on PATH) for better-looking graphs. Otherwise Mermaid is used, with less polished layouts.

Start at the [index](index.livemd). [Getting Started](getting_started.livemd)
covers application usage; the [tutorial chapters](egglog-tutorial/README.md) teach egglog.

## Setup

Open the index in Livebook and run the setup cell in any linked notebook.
Setup installs EgglogElixir and Kino from Hex. The library itself has no Kino
dependency.

Tutorial setup defines `next.(previous, code)` using `Egglog.Program.Step`.
Each step replays its source in a scoped Program; displaying a saved step does
not rerun it. Reexecuting cells repeats schedules and external effects.
After editing a predecessor, reevaluate its dependents.

## Scope and attribution

Chapters 01–06 follow the [upstream tutorial](https://egraphs-good.github.io/egglog-tutorial/)
([source](https://github.com/egraphs-good/egglog-tutorial), revision
`3b1d858cbde093cbccd76ed02192021248112cad`), copyright 2025 egraphs-good,
under the [MIT license](egglog-tutorial/LICENSE-UPSTREAM.md). Getting Started is original.

Elixir cells execute; egglog fences and Rust exercises are reading material.
Experimental back-off scheduling, dynamic-cost extensions and the Rust compiler
are reference material. Adaptations use supported BigRat constructors, expanded
ruleset annotations, explicit expected failures and corrected example names.
Upstream prose and lesson order are retained.

## Graphs and checks

`render: :auto` uses native DOT → Graphviz → SVG, otherwise native JSON → Mermaid.
Views cap serialization at 12 functions and 6 calls per function, with one leaf
inlining pass. Omission notices identify partial views; caps do not bound reasoning.
Mermaid preserves graph semantics but cannot reproduce Graphviz layout exactly.

To test the checkout, run `elixir scripts/check_livebook_cells.exs` and repeat
with `--no-dot`. This checks cell replay, earlier-step revisits and both
automatic renderer paths using the local wrapper.
