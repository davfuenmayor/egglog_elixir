# Livebooks

> **⚠️ Warning:** Install Graphviz (`dot` on PATH) for better-looking graphs. Otherwise Mermaid is used, with less polished layouts.

Start at the [index](index.livemd), then [Getting Started](getting_started.livemd)
for application usage or the [tutorial chapters](egglog-tutorial/README.md).

## Run

```sh
livebook server livebooks/index.livemd
```

Use the default Standalone runtime and preserve the checkout layout. Tutorials
install the local wrapper and Kino; Getting Started can also install GitHub main
when imported without a checkout. Prepare dependencies before class.
Requirements and bundles: [installation](../README.md#installation-and-platforms).
The wrapper itself has no Kino dependency.

## Lesson scope and attribution

Chapters 01–06 follow the [upstream tutorial](https://egraphs-good.github.io/egglog-tutorial/)
([source](https://github.com/egraphs-good/egglog-tutorial), revision
`3b1d858cbde093cbccd76ed02192021248112cad`), copyright 2025 egraphs-good,
under the [MIT license](egglog-tutorial/LICENSE-UPSTREAM.md). Getting Started is original material.

Elixir cells execute; egglog fences and Rust exercises are reading material.
The pinned engine lacks upstream experimental back-off scheduling and dynamic-cost
extensions. Chapters 05–06 illustrate native matrix syntax, dimensions and rewrites;
they do not execute the Rust compiler or experimental optimizer.

Adaptations include supported BigRat constructors, expanded ruleset annotations,
expected failures wrapped in `fail`, corrected mismatched example names, and
runnable distributivity/free-variable solutions. Upstream prose and order remain.

## Execution and revisiting cells

Tutorial setup installs dependencies, implements Kino display, configures graph
limits, and binds `next` to `Egglog.Program.Step.next/3`:

```elixir
step_02 = next.(step_01, "(edge 1 2)")
```

`Step.new()` creates step zero. Each next step replays accumulated source in a
scoped Program and retains the new snapshot; no handle persists. Earlier steps
can be revisited or branched. Replay repeats schedules and external effects.
After editing a predecessor, reevaluate its dependents. Displaying saved results
does not rerun egglog. `consolidate_protocols: false` enables notebook-local display.

Program runs clone the loaded base; EGraph calls retain mutation. Use
`Egglog.EGraph.with_egraph` for scoped mutable work, with `Egglog.EGraph.push`
and `Egglog.EGraph.pop` paired inside a cell and pop in `after`. Native errors
can retain preceding mutations. Scoped helpers close even on failure; return
results, not handles. Closed handles return `{:error, {:closed, message}}`.

`Egglog.Program.query!` returns typed bindings; `Egglog.EGraph.clear_function`
removes table rows while keeping declarations. Extraction selects a representative,
not a canonical form. A failed check means not established, not disproven.
API examples and ownership guidance: [Getting Started](getting_started.livemd).

## Rendering and limits

`render: :auto` uses **native DOT → Graphviz → SVG** when `dot` is found,
otherwise **native JSON → wrapper converter → Mermaid**. Conversion does not parse
DOT. Discovery checks `EGGLOG_GRAPHVIZ_DOT`, `GRAPHVIZ_DOT`, then PATH; overrides name
executables without arguments. Automatic SVG failure retains native DOT.

Views cap serialization at 12 functions and 6 calls per function, with one leaf
inlining layer. Omission notices identify partial views; empty declaration/reset
graphs are expected. Increase setup limits for larger views. Caps do not reduce
reasoning work. Output limits and caller timeouts do not cancel native execution;
`render_timeout` only limits Graphviz.

Dashed boxes denote classes; white nodes denote constructors. Cross-class arrows
end at class boundaries; internal edges retain member targets. Numbered edges
preserve argument order. Mermaid routing, label placement and box sizes differ
from Graphviz. Pictures are not proof traces.

## Verification

```sh
elixir scripts/check_livebook_cells.exs
elixir scripts/check_livebook_cells.exs --no-dot
```

The checker repeats cells and revisits earlier steps. Real Livebook checks use
disposable copies; browser checks separately verify rendered graphics. Commands:
[Livebook checks](../README.md#livebook-checks) and
[graph comparison](../README.md#graphvizmermaid-comparison-checks).
