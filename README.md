# EgglogElixir

Thin Elixir wrapper around the native Rust `egglog` engine.

The wrapper is intentionally small. Elixir does not implement congruence
closure, e-matching, Datalog evaluation, equality saturation, scheduling, or
extraction. Those stay inside native egglog.

## API Shape

The library exposes two main models:

* `Egglog.Program` for reproducible query-local runs. Load a base theory once;
  each query runs against a native clone of that loaded base. Query-local facts
  do not mutate the base.
* `Egglog.EGraph` for interactive mutable sessions. Each successful run mutates
  one native e-graph owned by an Elixir process. Native `(push)` / `(pop)`
  rollback points are exposed through `push/2` and `pop/2`.

Both APIs accept raw egglog source, and both can reuse parsed `Egglog.Commands`
handles when the same command sequence is run repeatedly.

Common operations:

* `load/2`, `load!/2`
* `run/3`, `run!/3`
* `check/4`, `check?/4`, `check_fail/4`
* `extract/4`, `extract!/4`
* `eval/4`, `eval!/4`
* `lookup/5`, `lookup!/5`
* `snapshot/3`, `snapshot!/3`
* `num_tuples/1`
* `close/1`

See the module docs for exact options and return shapes.

## Snapshots

For debugging and teaching examples, use `Egglog.snapshot/3` or
`Egglog.snapshot!/3` for query-local program snapshots, or
`Egglog.EGraph.snapshot/2` for the current mutable session.

Snapshots ask native egglog to serialize the e-graph. The wrapper can return
DOT, SVG, or JSON:

* `render: :auto` returns SVG when Graphviz's `dot` executable is available and
  falls back to DOT.
* `render: :dot` returns DOT.
* `render: :svg` requires SVG rendering.
* `render: :json` returns egglog's JSON serialization.

`Egglog.Snapshot.summary/1` provides small JSON snapshot summaries for notebooks
and tests. The wrapper itself has no Livebook or Kino dependency.

## Concurrency

`Egglog.Program` calls against the same handle are safe and isolated. They are
serialized by that one native resource while egglog clones and runs from the
loaded base. Separate `Program` handles are separate native resources.

`Egglog.EGraph` is stateful and uses one owner process for a mutable native
session. Concurrent callers are serialized through normal BEAM message passing.

There is no process-wide NIF mutex and no Elixir worker pool.

## Livebooks

The library includes Livebook examples and treats them as the primary
onboarding material.

Start here:

* [`livebooks/getting_started.livemd`](livebooks/getting_started.livemd)

That notebook gives a compact overview of:

* equality saturation and extraction
* snapshots and visualization
* congruence closure
* Datalog-style facts
* analysis facts as guards
* `Egglog.Program` vs `Egglog.EGraph`

Then continue with the chapter-by-chapter upstream tutorial adaptations:

* [`livebooks/egglog-tutorial/README.md`](livebooks/egglog-tutorial/README.md)

Those tutorial clones execute the ordinary egglog-language material through the
thin wrapper. Upstream sections that depend on experimental scheduler commands,
dynamic cost models, or Rust-library extension hooks are marked in the notebooks
as reference material instead of being reimplemented in Elixir.

## Requirements

This project uses Rustler, so compiling the NIF requires Rust and Cargo.

For local development:

```bash
mix deps.get
mix test
```

For Livebook, the Livebook runtime also needs `cargo` on `PATH`. Graph
visualizations additionally need Graphviz's `dot` executable on `PATH`.

The NIF crate lives in `native/egglog_nif` and depends on the upstream Rust
`egglog` crate by a pinned Git revision. It does not require a sibling checkout
of the upstream egglog repository.
