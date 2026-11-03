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
DOT, SVG, JSON, or Mermaid:

* `render: :auto` returns SVG when Graphviz completes successfully and falls
  back to native DOT if Graphviz is missing, fails or times out.
* `render: :dot` returns DOT.
* `render: :svg` requires SVG rendering.
* `render: :json` returns egglog's JSON serialization.
* render: :mermaid converts native JSON into Mermaid source, without Graphviz.

`Egglog.Snapshot.summary/1` provides small JSON snapshot summaries for notebooks
and tests. The wrapper itself has no Livebook or Kino dependency.
`Egglog.Output.print/2` prints only text returned by native egglog.

SVG rendering has a separate `render_timeout: 30_000` millisecond default.
Expiration kills Graphviz. Explicit SVG requests return
`{:error, {:graphviz_timeout, milliseconds}}`; automatic rendering returns DOT.
This does not cancel or roll back native egglog execution. Use native snapshot
limits to reduce diagrams, or `render: :dot` / `render: :json` to skip SVG layout.

## Mermaid snapshots in Kino

```elixir
snapshot = Egglog.Program.snapshot!(program, input, render: :mermaid)
Kino.Mermaid.new(snapshot.mermaid)

# Mutable sessions use the same option:
snapshot = Egglog.EGraph.snapshot!(egraph, render: :mermaid)
Kino.Mermaid.new(snapshot.text)

# Convert existing JSON without rerunning egglog:
source = Egglog.Snapshot.to_mermaid!(json_snapshot)
Kino.Mermaid.new(source)
```

Mermaid snapshots have format: :mermaid and identical text/mermaid source.
They retain native json, original result, statistics, and omission metadata.
mermaid_path (or path) exports .mmd; json_path exports the same native input.
No DOT/SVG is generated in this mode. Core has no Kino dependency.

Each e-class is a subgraph containing constructor nodes and a circular =
anchor. Argument edges target class anchors rather than selected representatives;
zero-based labels preserve argument positions. Types/let aliases label classes.
Sharing, repeated arguments, cycles and subsumed nodes are retained. Labels are
escaped and IDs are deterministic for a given snapshot. Layout differs from DOT.

Large sources may exceed the frontend's text/edge limits or be unreadable.
The exporter does not silently truncate. Use snapshot_max_functions /
snapshot_max_calls_per_function and display snapshot.omitted. The Analysis
Livebook demonstrates a capped view alongside uncapped JSON summaries.
A Kino object alone does not prove browser-side rendering succeeded.

## Concurrency

`Egglog.Program` calls against the same handle are safe and isolated. They are
serialized by that one native resource while egglog clones and runs from the
loaded base. Separate `Program` handles are separate native resources.

`Egglog.EGraph` is stateful and uses one owner process for a mutable native
session. Concurrent callers are serialized through normal BEAM message passing.

There is no process-wide NIF mutex and no Elixir worker pool.

## Livebooks

The library includes Livebook examples as its primary onboarding material.
Read [installation, execution contracts and limits](livebooks/README.md) first.
Independent experiments use scoped Program phases; Getting Started also has
an explicit sequential EGraph accumulation/rollback lesson. Chapter 06 is a
reference-only Rust guide with no executable setup.

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

## Installation and platforms

Use this checkout as a dependency, with Elixir 1.19+ and 64-bit Erlang/OTP 27+:

```elixir
{:egglog_elixir, path: "../egglog_elixir"}
```

Mix installs a matching, checksum-verified Rustler NIF without Cargo, a compiler,
or an egglog installation. Linux x86-64/ARM64 (glibc) and Windows x86-64 bundles
are included. macOS Intel/Apple Silicon build recipes are prepared but require
Mac runners before binaries can be shipped and validated. musl/Alpine is excluded.
See [MULTIPLATFORM.md](MULTIPLATFORM.md) for exact build/test status and baselines.

Graphviz is optional: default snapshots show SVG if `dot` is available, otherwise
DOT text. JSON and Mermaid work without Graphviz; Livebook views use Mermaid. All notebook examples
run through native egglog, and the default Standalone Livebook runtime works.

```sh
mix deps.get
mix test
mix escript.install hex livebook 0.19.9 --force
~/.mix/escripts/livebook server livebooks/getting_started.livemd
```

On Windows, launch Livebook from PowerShell:

```powershell
& "$HOME\.mix\escripts\livebook.bat" server livebooks/getting_started.livemd
```

Open the printed local URL, keep the checkout in its original layout, and choose
**Evaluate all** with the default **Standalone** runtime. The first Kino/dependency
installation needs network access. The notebook sources are retained verbatim;
this bundled installation supersedes their source-build prerequisite notes.

### Build or bring your own binaries

Run `scripts/build_native.sh` with Rust/Cargo 1.91+ and a linker, then use
`mix compile` normally. `EGGLOG_BUILD=1 mix compile` explicitly rebuilds;
`config :egglog_elixir, build_from_source: true` is still supported.

Mac users need Xcode Command Line Tools and native Rust. Windows users can use
Rust MSVC/Visual Studio Build Tools or Rust GNU/POSIX MinGW from Git Bash.
Set `EGGLOG_ELIXIR_BUNDLE` to an external archive's absolute path to use your
own binaries; keep its `.sha256` alongside it. Local builds allow CPU tuning
and verification on your own OS; performance/reliability gains need measurement.
Restart the runtime after replacing a NIF. Full commands are in
[MULTIPLATFORM.md](MULTIPLATFORM.md).

The wrapper pins egglog 3.0.0 in `native/egglog_nif/Cargo.toml` and its lockfile;
no sibling upstream checkout is required. Bundles retain the wrapper, upstream
and third-party notices. See [API coverage](API_COVERAGE.md) and
[known issues](KNOWN_ISSUES.md).

### Native release assets

The old opt-in RustlerPrecompiled download setup is replaced by bundled archives.
Normal builds no longer depend on unpublished GitHub releases. Build each target
with `scripts/build_native.sh`, then review and commit its archive/checksum.
For an explicitly requested GitHub release, tag the reviewed commit as `v0.2.0`
and run `MIX_ENV=prod mix run scripts/publish_native.exs` with authenticated
GitHub CLI access. It checks the clean tagged source and archive hashes and
refuses to replace an existing release. Builds never publish anything.

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

The checker uses real Livebook sessions and disposable notebook copies.
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
using Livebook's parser, runtime, actual `Mix.install` cells and Kino.
The reference-only compiler chapter has no code cells. The cell checker also
reruns each executable cell consecutively and revisits early phases after later
ones; it checks theory-edit/reload behavior as well as full notebook passes. Graphviz
is needed only for optional SVG rendering. Import warnings and evaluation errors
fail the check. Markdown-only examples stay Markdown; executable cells must be
Elixir. Each session evaluates a disposable notebook copy, so autosaves cannot
change your authoritative Livebooks, and closes afterward. The checker relies
on Livebook internals, hence the pinned version. `mix test` additionally checks
the setup dependency paths and wrapper examples without running a server.
Append notebook paths such as `livebooks/getting_started.livemd` to the checker
command to rerun selected files.


### Mermaid browser regression checks

Capture actual sources passed to Kino and its bundled frontend assets:

```sh
EGGLOG_MERMAID_EXPORT_DIR=/tmp/egglog-mermaid-corpus \
  elixir scripts/check_livebook_cells.exs --no-dot
EGGLOG_MERMAID_EXPORT_DIR=/tmp/egglog-mermaid-corpus mix test
```

Use a fresh corpus directory. The second command adds empty, escaped-label,
cyclic/repeated-edge and subsumed/root fixtures. The checker extracts the
installed Kino's own Mermaid assets into corpus/kino-assets.

Install the dev-only browser dependency outside the wrapper:

```sh
npm install --prefix /tmp/egglog-mermaid-browser playwright
/tmp/egglog-mermaid-browser/node_modules/.bin/playwright install --with-deps chromium
NODE_PATH=/tmp/egglog-mermaid-browser/node_modules \
  node scripts/check_mermaid_browser.cjs \
  /tmp/egglog-mermaid-corpus/kino-assets /tmp/egglog-mermaid-corpus
```

The browser check requires rendered SVG and verifies node/edge counts,
so a parser error or an oversized-source error diagram cannot pass.
It also verifies escaped label text. Playwright is a test tool, not a
library dependency. Real Livebook session checks remain separate.
