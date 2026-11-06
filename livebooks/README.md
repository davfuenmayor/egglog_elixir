# Livebooks: installation and execution contracts

Start with [Getting Started](getting_started.livemd), then the
[chapter index](egglog-tutorial/README.md). These library chapters explain the wrapper/native API and remain self-contained
when this checkout is used outside the course workspace.

## Installation and publication

Use this checkout as the dependency. Each executable notebook includes its
correct path relative to its own directory; keep the folder structure intact.
There is currently no published Hex package/release documented by this checkout.
Do not replace the local dependency with a hypothetical version.

The maintained requirements and platform matrix are in
[the root README](../README.md#installation-and-platforms) and
[MULTIPLATFORM.md](../MULTIPLATFORM.md): Elixir 1.19+, 64-bit OTP 27+, with
the supported bundled-native platforms listed there. Normal supported installs
need no Rust compiler. Other platforms follow the documented source-build route.
First dependency installation needs network access.

Install the documented Livebook version and open, from the project root:

~~~sh
livebook server livebooks/getting_started.livemd
~~~

Use the default Standalone runtime. Visual examples use render: :auto: Graphviz
SVG when dot is detected, otherwise native JSON converted to Kino.Mermaid.
Discovery checks EGGLOG_GRAPHVIZ_DOT, then GRAPHVIZ_DOT, then dot on PATH.
Overrides must name executables; invalid values are ignored. Paths with spaces
are supported without shell quoting inside the value. A detected renderer that
fails/times out returns raw native DOT. Explicit render: :svg requires Graphviz. One rendered snapshot preserves its
native result and DOT or JSON; displaying it does not rerun the query.

## Execution contracts

### Independent experiments: Program

Program loads a base, then executes each query on a clone of that base.
Queries are independent: lets/facts from one query are not inputs to the next.
A returned result or snapshot is ordinary data and can outlive the handle.

Getting Started uses theory/input values and scoped with_program calls.
Chapters 01–05 use explicit immutable source phases:

~~~elixir
step_02 = "... native commands ..."
phase_02 = phase_01 <> "\n" <> step_02
result = Egglog.Program.with_program(phase_01, fn program ->
  Egglog.Program.run!(program, step_02)
end)
~~~

These names are source strings, not handles. Loading a baseline executes its
prefix (including earlier schedules/checks), and the current step executes on
a clone. A view reconstructs the explicitly named phase. No hidden session is
reset, no persistent graph is silently cloned, and no wrapper scheduler is added.
Reconstruction costs more than maintaining an incremental graph.

Evaluate definitions before dependents. After changing a step/theory, reevaluate
dependent phases and views. Returning to an earlier phase after a later one is
safe. Repeating a declaration cell does not redeclare into a leftover native graph.

### Intentional state: EGraph

EGraph runs mutate one session. Repeating a declaration or push changes that
same state; this is its intended contract, not a defect. Getting Started contains
a sequential accumulation/push/pop demonstration inside one scoped cell.
Its individual calls run in order; rerunning the whole cell starts a fresh scope.

For a deliberately long-lived session outside that example: create it, execute
the documented steps in order, then close it. To reconstruct its initial state,
close the old handle and create a new graph from the original source. Do not
pretend every state-mutating step is an independent experiment or make a display
helper silently reset it. Native push/pop supplies explicit rollback points.

### Lifetime and errors

with_program/with_egraph close in after, even when execution raises.
Do not return a handle for use outside the scope. close does not reset or reopen
a handle; the documented closed error requires reconstructing the experiment.

An already-loaded Program retains its original theory after an Elixir string
is edited. Reload the theory or rerun the scoped experiment. Native mutable
errors may retain preceding mutations: there are no automatic transactions.
Use explicit native rollback/reconstruction when needed.

## What actually executes?

- **Elixir fences:** executable Livebook cells; native source is passed in strings.
- **egglog/text fences:** illustrative object-language source, not separate executions.
- **Marked experimental/reference blocks:** reading material only.
- **Chapter 06:** a reference-only Rust-embedding guide with no executable cells.
  Successful chapter checks do not mean its compiler is implemented in Elixir.

The native examples in chapters 01–05 remain visible and in upstream teaching
order. Standard rulesets/schedules and static costs execute; experimental
schedulers/dynamic costs and Rust extension hooks retain explicit scope labels.

## Equality, execution, and limits

A rewrite declaration does not apply it. Seed queried terms before running.
A newly generated subterm may enable a rule only in the next round; chapter 01
shows before/one-round/two-round results. A successful check uses supplied
assumptions. An expected fail(check) means not established in that run, not a
countermodel or a completeness result.

| Control | What it controls | What it does not guarantee |
| --- | --- | --- |
| run rounds / bounded repeat | Rule rounds or repeated schedule steps | Universal validity, completeness, wall-clock or memory bounds |
| saturate | Runs until a native fixed point is detected | Termination on every theory |
| Native work/caller waits | Native execution has its own lifecycle; wrapper waits indefinitely | A caller timeout is not cancellation |
| output_limit | Truncates returned command outputs after execution | Stopping native computation or limiting its memory |
| snapshot_max_functions / calls | Caps native serialization | Limiting the native graph or engine workload |
| snapshot_inline_leaves | Changes the serialized view | Simplifying the engine's actual terms |
| render_timeout | Bounds the Graphviz renderer | Cancelling the native run |
| Mermaid browser limits | Bound what the frontend can parse/layout | Native proof failure or safe automatic truncation |

Partial views must display snapshot.omitted. Analysis has capped automatic views
and adjacent uncapped JSON summaries. Layout movement and snapshot differences
are not proof traces. Native child references, zero-based argument labels, aliases, sharing,
parent coalescing, cycles and subsumed nodes are explained in notebook legends.

Extraction chooses representatives by native cost/ties. A normalization law
does not guarantee a canonical printed result. Native integer remainder retains
the sign of a negative dividend: (-1)%5 = -1, whereas ((n%5)+5)%5 gives 0…4.
Compound i64 arithmetic also needs attention to intermediate overflow; it is
not arbitrary-precision mathematical integer arithmetic.

## Verification

The cell checker reads the actual notebooks, executes every executable cell
twice consecutively, and revisits earlier cells after later phases. It checks
explicit expected errors/rollback behavior in the examples. Whole-notebook passes,
individual phase revisits and browser rendering are different checks.

See [the root README](../README.md#livebook-checks) for commands and real
Livebook/browser validation. No browser or Graphviz is required by the core API.
