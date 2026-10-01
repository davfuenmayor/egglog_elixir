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
| `serialize` | `run(..., snapshot: ...)`, `snapshot` helpers | Native DOT/JSON; limits map to `SerializeConfig`; native leaf inlining and primitive splitting. |
| `CommandOutput`, run reports | Run result maps | Native output text; per-call totals aggregate schedules, excluding cumulative `(print-stats)` output. Rule names remain strings. |

`Egglog` delegates to `Program`; bang variants raise. `Program.with_program/3`
and `EGraph.with_egraph/1,2,3` return callback results and close in `after`.
`close/1` releases the native resource; mutable close also waits for its server
to stop. A creator monitor bounds mutable-server lifetime. Calls wait indefinitely
because waiting timeouts do not cancel native execution. Caught panics discard
the affected handle, including a reusable program base; ordinary native errors
do not close it. Unexpected server exits retain `{:session_exit, reason}`.

Options accept keyword lists or maps, including known string keys. Invalid,
unknown, duplicate, or out-of-range options return `{:error, {:invalid_option,
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

`Snapshot` decodes and summarizes upstream JSON. SVG rendering invokes Graphviz;
no graph execution, rewriting, or extraction is reimplemented in Elixir.
`Output.texts/2` and `Output.print/2` use only native result text. SVG rendering
has a separate `:render_timeout` (30,000 milliseconds by default); expiration
kills the renderer and returns a tagged error without changing native state.

## Verification

Run `mix test` and `cargo test --locked --manifest-path native/egglog_nif/Cargo.toml`.
Integration tests cover clone isolation, concurrent callers, creator lifetime,
checks and type errors, report aggregation, extraction truncation, parsed commands,
option validation, native partial mutation, snapshots and artifact failures.
Native tests cover panic cleanup. Published multi-platform artifacts remain
outside this local verification; only the Linux x86_64 GNU artifact is prepared.

Local verification: **70 ExUnit checks (69 tests, 1 doctest)** and **2 native
panic-cleanup tests** pass. Documentation generation with warnings as errors,
formatting, and Clippy also pass. A separate consumer downloaded, checked and
loaded the prepared native archive from local HTTP with Cargo absent from PATH.
The locked native dependency graph also compiles with the documented Rust 1.91.0
minimum.

`scripts/check_livebooks.exs` evaluates disposable copies in real Livebook 0.19.9
sessions, including `Mix.install`, Kino and Graphviz SVG rendering. Equality
Saturation, Datalog, Scheduling, Cost Model and Extraction, Case Study, and Getting
Started pass: **114 executable cells**. Analysis returns a rendering timeout
at its first large SVG layout; see [KNOWN_ISSUES.md](KNOWN_ISSUES.md). The remaining Analysis cells have
not passed this full check. These checks evaluate notebook outputs; they do not
automate browser interaction or visually inspect diagrams.
