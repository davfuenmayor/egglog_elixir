# Livebooks

Open the [notebook index](index.livemd) to choose a lesson, or begin with
[Getting Started](getting_started.livemd) for the library tour. Installation, wrapper mechanics and
renderer details are collected here and illustrated in Getting Started; the six tutorial
chapters follow the upstream tutorial text.

## Upstream text and attribution

The lesson text comes from the [egglog tutorial](https://egraphs-good.github.io/egglog-tutorial/)
and its [source repository](https://github.com/egraphs-good/egglog-tutorial),
revision `3b1d858cbde093cbccd76ed02192021248112cad`.
Copyright (c) 2025 egraphs-good; reproduced under the
[MIT license](LICENSE-UPSTREAM.md). Chapters 01–06 retain the upstream prose and
order; Getting Started is original library onboarding material.

The adaptations are limited to Livebook setup, executable Elixir cells, graph
views, local compatibility fixes, and short captions for native graph illustrations.
Web-demo directions refer to the graph below instead. Obvious mismatched example
expressions/printed comments in chapter 01, the edge/path atom typo in chapter 02,
and the free-variable exercise's expression name are corrected.

Every executable native batch returns a graph with `render: :auto`. Outputs from
checks/extraction/table commands are printed alongside it. There are no JSON
summary cells. Graphs are captured **before** `pop` as well as after rollback,
so temporary results remain visible. An empty graph after declarations or reset
is shown honestly; the display does not invent terms to fill it.

## Installation

Keep the checkout's folder structure. Tutorial notebooks install the local wrapper
using its path relative to that notebook, plus Kino. Getting Started additionally supports
standalone badge imports by installing the GitHub main version when no local
checkout is present. Use the default Standalone
runtime. Prepare dependencies before class; first installation needs network access.

From the project root, with Livebook installed:

~~~sh
livebook server livebooks/index.livemd
~~~

Elixir/OTP requirements, bundled-native platforms, and source builds are documented
in [the root README](../README.md) and [MULTIPLATFORM.md](../MULTIPLATFORM.md).
Supported bundled installs require no Rust compiler.

## What runs, and what remains upstream reference material?

| Notebook | Executable material |
| --- | --- |
| Index | Navigation only; no executable cells or dependencies |
| Getting Started | The same arithmetic example with EGraph (push/pop) and Program (independent runs), queries and errors |
| 01 — Equality Saturation | Terms, rules, checks, extraction, distributivity exercise |
| 02 — Datalog | Relations, shortest paths, equality, push/pop |
| 03 — E-class Analysis | Bounds, guarded rewrites, extraction, free-variable exercise |
| 04 — Scheduling | Native rulesets and run/repeat/saturate schedules |
| 05 — Extraction and Cost | Static costs; matrix syntax, dimension facts and associativity graph illustrations |
| 06 — LA compiler | Native schema, GEMM expression and rewrite graph illustrations from the referenced case study |

Elixir fences execute. Egglog fences and indented code in the upstream prose are
reading material paired with executable cells where supported. Pseudocode and
Rust extension exercises are not executed by Livebook.

The pinned native engine does not provide the upstream experimental back-off
scheduler or dynamic-cost extension. The corresponding prose and source examples
remain intact in chapters 04–06. Chapter 05's added graphs illustrate matrix
syntax, dimension analysis and equivalent terms; they do **not** claim that the
experimental cost model ran or selected an optimum. Chapter 06's graphs use the
ordinary datatype/rewrite subset of the upstream case-study schema. The Rust
parser/compiler, custom scheduler and cost-model exercises remain upstream work.

Compatibility adaptations in executable cells:

- BigRat constants use the installed native engine's supported exact constructors.
- Experimental `with-ruleset` sugar is expanded into native `:ruleset` annotations.
- Deliberately failing checks are wrapped in native `fail`.
- Chapter 01 seeds an Add probe for the not-yet-run commutativity example, whose
  upstream expression otherwise has the wrong root. Its distributivity example
  includes the required rewrite so a complete notebook evaluation succeeds.
- Chapter 03 supplies the remaining constructor cases for the free-variable
  exercise and uses four native rounds for its runnable illustration. The
  upstream saturation suggestion remains in the exercise text.

## Execution and revisiting cells

A `Step` is a numbered point in the lesson's execution history. `new/0` creates
step zero; `next/3` constructs a following step without changing its predecessor.
Each lesson cell declares its predecessor and its egglog code:

~~~elixir
step_02 =
  next.(step_01, """
  (edge 1 2)
  (edge 2 3)
  """)
~~~

The setup cell installs dependencies, registers the display adapter, initializes
`step_00 = Egglog.Program.Step.new()`, and binds `next` to
`Egglog.Program.Step.next/3` with the shared `render: :auto` and graph limits.
A step contains accumulated `source` and the current `snapshot`, with no open
native handle. `next/3` loads the predecessor's source in a scoped Program,
executes the new code on a clone, captures its snapshot, and closes the handle.
It returns a new step; previous steps are unchanged and can be branched from.
Errors raise and leave the predecessor usable.

The setup implements `Kino.Render` for steps. Returning a step at the end of a
cell automatically displays the current step's native output, omission/empty-view
notices, and graph. Previous steps' output is not repeated. Displaying a retained
step does not execute egglog. Inspect `step.source` or `step.snapshot` explicitly
when needed; ordinary inspection prints a compact description instead of source.
The notebook installs dependencies with `consolidate_protocols: false` so this
local display implementation takes effect. The wrapper has no Kino dependency.

Loading a step reexecutes that prefix, including earlier checks/schedules. This
costs more than a mutable incremental session, but makes returning to an earlier
cell safe. No hidden reset, scheduler or Elixir reasoning engine is involved.
Evaluate definitions first; after editing source, reevaluate its dependents.

A rewrite declaration does not apply it. Seed terms before running rules. A new
subterm may require another round before it can simplify. A successful check
uses the supplied assumptions; an expected `fail(check)` means not established
in that run, not a countermodel or completeness result.

## Rendering and graph limits

The rendering paths are **native egglog DOT → Graphviz `dot` → SVG** and
**native egglog JSON → the wrapper's JSON-to-Mermaid converter → Mermaid source
→ Kino's Mermaid renderer**. Mermaid conversion does not parse DOT. The wrapper
has no Kino dependency; each notebook installs Kino separately for display.

Automatic rendering prefers the DOT/SVG path when `dot` is detected, otherwise
it uses the JSON/Mermaid path. Discovery checks
`EGGLOG_GRAPHVIZ_DOT`, then `GRAPHVIZ_DOT`, then `dot` on PATH. Overrides name an
executable path or command, without arguments; invalid values are ignored and
paths with spaces are supported. A detected renderer failure/timeout retains DOT.

The shared Kino display adapter only presents retained data. It does not run
egglog. The `next` closure requests `render: :auto` for every stage. The setup's
`graph_limits` caps serialization at 12 functions and 6 calls per function, and
inlines one layer of leaves to keep ubiquitous views readable. Native omission
metadata is displayed as a partial-view notice. Increase those values to inspect
more; they do not cap the native engine's work or change a check's result.

Graphviz is the visual reference. Classes are dashed colored boxes and constructors
are white inner nodes. Cross-class arrows terminate at the outer class boundary;
internal arrows retain member endpoints, including self-loops. Types determine
colors, and metadata labels include let aliases. Mermaid uses a standard subgraph
for every class and numbers multi-argument edges to preserve argument order;
redundant unary zeros are omitted. It does not add equality-anchor vertices.

Mermaid box sizes, member positions, source attachment and label positions remain
automatic. Native IDs and layout positions are not stable names across separate
runs. Follow aliases and ordered arguments. Pictures are not proof traces.

| Control | Effect | Does not guarantee |
| --- | --- | --- |
| run rounds / repeat | Native rule rounds / schedule steps | Completeness or a wall-clock limit |
| saturate | Iteration toward a native fixed point | Termination on every theory |
| output_limit | Returned output truncation | Native cancellation or a memory bound |
| snapshot limits / inlining | Size and form of the serialized view | Less native reasoning work |
| render_timeout | Graphviz layout deadline | Cancelling egglog |
| Mermaid frontend limits | Browser parsing/layout capacity | A failed equality proof |

Extraction chooses a representative according to native costs and ties; it does
not delete alternatives or promise canonical output. Native integer remainder
keeps the negative dividend's sign, and compound i64 arithmetic may overflow.

## Additional wrapper APIs

These API details are kept out of the upstream lessons. Program queries are
independent; a loaded Program retains the theory it was loaded from, even if an
Elixir source string is later edited. Reload the theory to change it.

EGraph intentionally retains mutation between calls. Use it for interactive state,
with explicit native push/pop rollback points:

~~~elixir
Egglog.EGraph.with_egraph("(relation seen (i64))", fn graph ->
  :ok = Egglog.EGraph.push(graph)
  Egglog.EGraph.run!(graph, "(seen 1)")
  {:ok, true} = Egglog.EGraph.check(graph, "(seen 1)")
  :ok = Egglog.EGraph.pop(graph)
  {:ok, false} = Egglog.EGraph.check(graph, "(seen 1)")
end)
~~~

`Egglog.Program.query!` and `EGraph.query!` return structured bindings; function
inspection returns schemas. `Egglog.EGraph.clear_function` removes rows while
retaining a declaration. Native errors can preserve preceding mutations; the
wrapper adds no transaction or automatic rollback.

`with_program` and `with_egraph` close in `after`, including on failure. Return
ordinary results, not handles for later use. A closed handle returns
`{:error, {:closed, message}}`; reconstruct it instead of trying to reopen it.
Mutable sessions also close when their creator exits.

Native `num_threads: 1` is serial; `0` uses available parallelism. Clones inherit
the loaded setting. Calls on a shared handle are serialized; independent graphs
can execute concurrently. Caller waits are infinite because a caller timeout
would not cancel native computation.

## Verification

The checker reads these notebooks and executes each cell twice consecutively,
then revisits earlier stages. The real Livebook checker separately imports and
evaluates disposable copies without autosaving over the sources. Both automatic
renderer branches are checked. Browser rendering is checked separately from merely
constructing a Kino object.

~~~sh
elixir scripts/check_livebook_cells.exs
elixir scripts/check_livebook_cells.exs --no-dot
~~~

See [the root README](../README.md#livebook-checks) for actual Livebook and browser
commands. No browser or Graphviz is required by the core wrapper API.
