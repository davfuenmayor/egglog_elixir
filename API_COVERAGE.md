# API coverage

Checked against egglog **3.0.0**, pinned revision
`b912caa9694c0c029f9ae3d91db0adc8824e14f5`. Native features: `graphviz`, `serde`;
the upstream CLI feature is disabled. This inventories the wrapper's supported
surface, not every API in the upstream workspace.

| Upstream operation | Elixir binding | Behavior |
| --- | --- | --- |
| `EGraph::default`, `new_with_proofs` | `Program.load/2`, `EGraph.new/2` | Source is loaded natively; optional proof support. |
| `parse_program` | `Commands.parse/1`, `Egglog.parse/1`, `Program.parse/1` | Native AST resource retains source for inspection helpers. |
| `run_program` | `Program.run/3`, `EGraph.run/3` | Source, command lists, or parsed commands. Program maps render native command syntax. |
| `EGraph::clone` | Program operations | Clone-local execution; calls on one program remain serialized. |
| Native check/extract commands | `check`, `check?`, `check_fail`, `extract` helpers | Failed checks are identified by Rust variants, not messages. Extraction returns the last request or an error if truncated. |
| `eval_expr` | `Program.eval/4`, `EGraph.eval/2` | Primitive values decoded; other values remain native text. Evaluation can mutate a mutable graph. |
| `Read::lookup`, `Read::eclass_of` | `Program.lookup/5`, `EGraph.lookup/3` | Arguments evaluated and sort-checked; functions use `lookup`, constructors use `eclass_of`; absent row returns `{:ok, nil}`. |
| `functions_iter`, `get_function`, `Function::func_type` | `functions/1`, `function/2` on both handles | Native declarations, sort names, subtype and visibility flags; unknown name returns `{:ok, nil}`. |
| `clear_function` | `EGraph.clear_function/2` | Clears native rows, retaining declarations; native rollback behavior. |
| `query` | `EGraph.query/3`, `Program.query/5` | Native pattern matching returns typed binding maps with string keys; proof incompatibility is returned as an error. |
| `set_num_threads`, `num_threads` | Load option `:num_threads`, `num_threads/1`, `EGraph.set_num_threads/2` | Per-graph configuration retained by clones; `1` is serial, `0` uses available parallelism. |
| Native push/pop commands | `EGraph.push/2`, `pop/2` | Native rollback points; no implicit wrapper transactions. |
| `num_tuples` | `Program.num_tuples/1`, `EGraph.num_tuples/1` | Upstream table counts, using dirty CPU scheduling. |
| `serialize` | `run(..., snapshot: ...)`, `snapshot` helpers | Native DOT/JSON plus JSON-derived Mermaid; limits map to `SerializeConfig`; native leaf inlining and primitive splitting. |
| `CommandOutput`, run reports | Run result maps | Native output text; per-call totals aggregate schedules, excluding cumulative `(print-stats)` output. Rule names remain strings. |

`Egglog` delegates to `Program`; bang variants raise. `Program.with_program/3`
and `EGraph.with_egraph/1,2,3` return callback results and close in `after`.
`close/1` releases the native resource; mutable close also waits for its server
to stop. A creator monitor bounds mutable-server lifetime. Calls wait indefinitely
because waiting timeouts do not cancel native execution. Caught panics discard
the affected handle, including a reusable program base; ordinary native errors
do not close it. Unexpected server exits retain `{:session_exit, reason}`.

Program/EGraph options accept keyword lists or maps, including known string keys.
Invalid, unknown, duplicate, or out-of-range options return `{:error, {:invalid_option,
message}}` before execution. Snapshot helpers return tagged rendering/file errors.
Output limits trim returned output after native execution; they do not cap native
memory or execution time. Snapshots and earlier artifact writes are not rolled
back if a later artifact write fails.

## Not exposed

- `SerializeConfig.include_temporary_functions` and `root_eclasses`.
- Direct row iteration, canonical-value access, report-level and strict-mode
  setters.
- Rust extension hooks, custom primitives/schedulers/commands, and structured
  proof reconstruction. Native commands supported by the pinned parser remain
  available through raw source; wrapper helpers are not the whole language API.

`Snapshot` decodes native JSON and converts it to Mermaid without native
reexecution. SVG is rendered from native DOT by Graphviz. `render: :auto` selects
SVG when Graphviz is detected, otherwise JSON/Mermaid; automatic renderer failure
retains DOT. `render_timeout` (30,000 ms by default) limits Graphviz, not egglog.
`Output.texts/2` and `print/2` expose native result text without synthesizing outcomes.

`Program.Step.new/1` and `next/3` are notebook utilities over Program, not another
execution model. They retain source and snapshots without open handles. `next/3`
reexecutes preceding source and raises on failure; it rebuilds the prefix before
validating the current snapshot options. No incremental execution/cache is implied.
Kino display implementations live in notebook setup; the library has no Kino dependency.

## Verification

Run `mix test` and `cargo test --locked --manifest-path native/egglog_nif/Cargo.toml`.
Integration tests cover clone isolation, concurrent callers, creator lifetime,
checks and type errors, report aggregation, extraction truncation, parsed commands,
option validation, native partial mutation, snapshots and artifact failures.
Native tests cover panic cleanup. Installation tests cover checksum/target/payload
validation, missing-file restoration, concurrent installs and relocation.
Platform-specific evidence and remaining release checks are recorded in
[MULTIPLATFORM.md](MULTIPLATFORM.md). Current local verification: **109 ExUnit
checks (108 tests, 1 doctest)** and documentation generation pass on Linux.
Earlier native panic-cleanup and package-install results are recorded separately;
they do not imply current native-platform validation on every target.

The collection contains one navigation-only index and seven executable notebooks:
Getting Started plus six upstream tutorial chapters. Their **111 executable cells**
include **98 Step snapshots** and **13 direct Program/EGraph snapshots**. Experimental
scheduler/cost-model and Rust extension sections remain reference material; ordinary
native compiler-schema illustrations execute.

- `scripts/check_livebook_cells.exs`: executes notebook source, repeats cells and
  revisits earlier steps; `--no-dot` tests automatic Mermaid fallback.
- `scripts/check_livebooks.exs`: imports/evaluates disposable copies in real
  Livebook/Kino, verifies graph display cells, and imports the index without a runtime.
- `scripts/graph_parity_capture.exs` and `scripts/native_graphviz`: capture retained
  native JSON/Mermaid and derive reference DOT without rerunning egglog.
- `scripts/check_mermaid_browser.cjs`: checks rendered labels, grouping, argument
  order and arrowheads against native DOT using Kino's bundled frontend.

Validation commands are in [README.md](README.md#livebook-checks). Supported API
limits are in [KNOWN_ISSUES.md](KNOWN_ISSUES.md); only open proposals belong in
[the improvement backlog](egglog_elixir_improvements.md).
