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
`Egglog.Output.print/2` prints only text returned by native egglog.

SVG rendering has a separate `render_timeout: 30_000` millisecond default.
Expiration kills Graphviz and returns `{:error, {:graphviz_timeout, milliseconds}}`;
it does not cancel or roll back native egglog execution. Use native snapshot
limits to reduce diagrams, or `render: :dot` / `render: :json` to skip SVG layout.

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

Source builds use release mode and require Elixir 1.19+, a compatible Erlang/OTP,
Rust/Cargo 1.91+, and a platform linker/C toolchain. Dependency resolution is
checked with `cargo metadata --locked` before Rustler compiles. Keep both lockfiles.
See [API coverage](API_COVERAGE.md) and [known issues](KNOWN_ISSUES.md).

For local development:

```bash
mix deps.get
mix test
```

For Livebook, the Livebook runtime also needs `cargo` on `PATH`. Graph
visualizations additionally need Graphviz's `dot` executable on `PATH`.

The wrapper targets egglog 3.0.0 at revision
`b912caa9694c0c029f9ae3d91db0adc8824e14f5`. Native pattern queries, declaration
inspection and per-graph thread configuration are documented in the public API.

The NIF crate lives in `native/egglog_nif` and depends on the upstream Rust
`egglog` crate by a pinned Git revision. It does not require a sibling checkout
of the upstream egglog repository.

### Native artifacts

Source compilation remains the default. The wrapper also supports
checksum-verified RustlerPrecompiled downloads for `x86_64-unknown-linux-gnu`
(NIF API 2.15). Enable downloads only after the matching release artifact is
published:

```elixir
config :egglog_elixir, build_from_source: false
```

Use `RUSTLER_PRECOMPILED_FORCE_BUILD_ALL=true` to force a source build. To prepare
a release archive locally, run `MIX_ENV=prod mix run scripts/package_native.exs`.
It writes an archive under `dist/` and updates `checksum-Elixir.Egglog.Native.exs`;
review and ship the checksum with the matching release. It does not upload anything.
Only the listed target has been verified; other platforms use source builds.

For publication, commit the reviewed sources and checksum, tag the matching
commit as `v0.2.0`, and push that commit/tag. Then run
`MIX_ENV=prod mix run scripts/publish_native.exs` with authenticated GitHub CLI
release access. The script verifies the clean tagged source and archive hashes,
and refuses to replace an existing release. After publication, consumers can
use the download configuration above without installing Rust.

Deployed source-built releases do not need Cargo. The tested Linux artifact links
against glibc (2.34+), libm and libgcc_s; Graphviz's `dot` is needed only for SVG rendering.
DOT and JSON snapshots work without Graphviz. Native artifact archives include
the wrapper and upstream MIT notices.

### Testing a local upstream checkout

Use Cargo's Git-source patch in an uncommitted local change to
`native/egglog_nif/Cargo.toml`:

```toml
[patch."https://github.com/egraphs-good/egglog.git"]
egglog = { path = "../../../egglog" }
```

Regenerate the local Cargo lockfile with `cargo update --manifest-path
native/egglog_nif/Cargo.toml`, then rebuild from source. Upstream's path-based
workspace dependencies follow that checkout. Restore the patch and lockfile
before distributing; normal installations retain the pinned Git revision.

### Livebook checks

The checker uses the same real Livebook session method as `rudof_elixir`.
Install the pinned Livebook version and start an isolated local server:

```sh
mix escript.install hex livebook 0.19.9 --force
epmd -daemon
LIVEBOOK_IFRAME_PORT=8192 ~/.mix/escripts/livebook server --ip 127.0.0.1 --port 8191 \
  --name egglog_livebooks@127.0.0.1 --cookie YOUR_LOCAL_COOKIE
```

From the project root, in another terminal:

```sh
elixir --name egglog_checker@127.0.0.1 --cookie YOUR_LOCAL_COOKIE \
  scripts/check_livebooks.exs egglog_livebooks@127.0.0.1
```

This evaluates every notebook under `livebooks/`, including Getting Started,
using Livebook's parser, runtime, actual `Mix.install` cells and Kino. Graphviz
must be installed to check SVG rendering. Import warnings and evaluation errors
fail the check. Markdown-only examples stay Markdown; executable cells must be
Elixir. Each session evaluates a disposable notebook copy, so autosaves cannot
change your authoritative Livebooks, and closes afterward. The checker relies
on Livebook internals, hence the pinned version. `mix test` additionally checks
the setup dependency paths and wrapper examples without running a server.
Append notebook paths such as `livebooks/getting_started.livemd` to the checker
command to rerun selected files.
