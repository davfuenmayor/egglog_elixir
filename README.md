# EgglogElixir

[![Run in Livebook](https://livebook.dev/badge/v1/blue.svg)](https://livebook.dev/run?url=https%3A%2F%2Fgithub.com%2Fdavfuenmayor%2Fegglog_elixir%2Fblob%2Fmain%2Flivebooks%2Findex.livemd)

Thin Elixir wrapper around the native Rust `egglog` engine.

The wrapper is intentionally small. Elixir does not implement congruence
closure, e-matching, Datalog evaluation, equality saturation, scheduling, or
extraction. Those stay inside native egglog.

## Structured parse errors

Parser failures preserve egglog’s diagnostic message and expose its source span:

```elixir
{:error, {:invalid_theory, message, location}} = Egglog.parse(")")
# location:
# %{file: nil, start_byte: 0, end_byte: 1,
#   start_line: 1, start_column: 1, end_line: 1, end_column: 2}
```

The same shape applies to loading. Execution and inspection use `:native_error`
instead of `:invalid_theory`. Locations come directly from native egglog, including
filenames for included files. Byte offsets are zero-based UTF-8 offsets; lines
and columns are one-based, and both byte and position ranges have exclusive ends.
Columns count Unicode code points, not bytes or graphemes; tabs count as one.
EOF ranges may be empty. If no user-source span exists, the location is nil.

Positions refer to the native parser’s input. For standalone expressions, facts,
or lookup arguments, they are local to that string. For structured requests,
they refer to the generated egglog command sequence; no field-level remapping is
performed. Other error shapes and failed-check behavior remain unchanged.
See `Egglog` module documentation for the full contract.

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
DOT, SVG, JSON, or Mermaid. The two graphical rendering paths are:

* **SVG:** native egglog DOT output → Graphviz `dot` → SVG.
* **Mermaid:** native egglog JSON output → the wrapper's JSON-to-Mermaid converter
  → Mermaid source, which Kino or another Mermaid frontend renders.

Mermaid is generated directly from JSON; the converter does not parse DOT.
The `render` option selects the output:

* `render: :auto` (the default) returns Graphviz SVG when a dot executable is
  detected; otherwise it converts native JSON to Mermaid. If a detected renderer
  fails or times out, it retains native DOT.
* `render: :dot` returns DOT.
* `render: :svg` requires Graphviz to render native DOT as SVG.
* `render: :json` returns egglog's JSON serialization.
* `render: :mermaid` converts native JSON into Mermaid source, without Graphviz.

`Egglog.Snapshot.summary/1` provides small JSON snapshot summaries for notebooks
and tests. The wrapper itself has no Livebook or Kino dependency.
`Egglog.Output.print/2` prints only text returned by native egglog.

SVG rendering has a separate `render_timeout: 30_000` millisecond default.
Expiration kills Graphviz. Explicit SVG requests return
`{:error, {:graphviz_timeout, milliseconds}}`; automatic rendering returns DOT.
This does not cancel or roll back native egglog execution. Use native snapshot
limits to reduce diagrams, or `render: :dot` / `render: :json` to skip SVG layout.

Graphviz discovery tries `EGGLOG_GRAPHVIZ_DOT`, then `GRAPHVIZ_DOT`, then `dot`
on PATH. Override values must be executable paths or command names, without
arguments or shell quoting; paths containing spaces are supported. Invalid or
non-executable values are ignored. Overrides also apply to explicit `:svg`.

```sh
export EGGLOG_GRAPHVIZ_DOT="/opt/Graphviz Suite/bin/dot"
```

Automatic snapshots have `format: :svg` with `svg`/`dot`, or `format: :mermaid`
with `mermaid`/`json`. They retain the selected native snapshot in `result`;
choosing a format does not rerun the query. Inspect `snapshot.format` in displays
and only request downloads for fields present in that result. Explicit `:dot`,
`:svg`, `:json`, and `:mermaid` retain their existing meanings.

## Automatic snapshots in Kino

```elixir
snapshot = Egglog.Program.snapshot!(program, input, render: :auto)
case snapshot do
  %{format: :svg, svg: svg} -> Kino.HTML.new(svg)
  %{format: :mermaid, mermaid: source} -> Kino.Mermaid.new(source)
  %{text: text} -> Kino.Text.new(text)
end
```

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

Mermaid matches the native DOT labelled graph: one vertex per serialized e-node,
the same equality-class grouping, and DOT-style class-boundary arrowheads. The
original child references are retained in source comments. It adds no
synthetic anchor vertices. White rounded nodes, dashed colored classes, fonts,
and native metadata titles follow Graphviz. IDs/types stay out of visible labels;
types determine the same Graphviz palette. Zero-based labels on multi-argument
edges replace DOT's argument ports; unary zeros are omitted. Shared children,
repeated arguments and self-loops survive. Every equality class is rendered as
one standard Mermaid subgraph; every constructor is one ordinary labelled node.
The renderer uses a single escaping path, without custom HTML or special singleton
boxes. It deliberately leaves box sizing and layout to Mermaid.

An edge's referenced node belongs to the argument's entire equality class; it is
not a preferred expression. Positions, class-member ordering and edge routing
can differ: Mermaid lacks DOT's same-rank and source-port constraints. Cross-class targets
are class boxes, matching DOT lhead; edges within a class retain member targets.
Subsumed flags and native identifiers remain in safe base64-JSON source comments;
roots use thicker borders. Labels are escaped and IDs are deterministic for a
given snapshot. Literal backslashes use Graphviz's display convention; the
original strings remain unchanged in the native JSON.

Large sources may exceed the frontend's text/edge limits or be unreadable.
The exporter does not silently truncate. Use snapshot_max_functions /
snapshot_max_calls_per_function and display snapshot.omitted. The Livebooks
show capped graph views with explicit omission notices.
A Kino object alone does not prove browser-side rendering succeeded.

## Replayable program steps

`Egglog.Program.Step` packages accumulated source and the current snapshot as
ordinary data, without retaining native handles or depending on Kino. A `Step`
names a point in execution history; `new/0` creates step zero and `next/3`
constructs a following step without changing its predecessor:

```elixir
initial = Egglog.Program.Step.new("(relation edge (i64 i64))")
first = Egglog.Program.Step.next(initial, "(edge 1 2)", render: :auto)
second = Egglog.Program.Step.next(first, "(edge 2 3)", render: :auto)
```

Each step reconstructs its predecessor in a scoped Program and captures the new
code's output and graph. Previous steps remain unchanged, so steps can be
repeated or branched. Errors raise, and scoped handles close on success or failure.
The Livebooks bind this operation as `next.(previous, code)` and supply a local
`Kino.Render` implementation to display output and graphs automatically. See the
[shared guide](livebooks/README.md#execution-and-revisiting-cells) for setup and
replay costs. SVG is rendered from native DOT; Mermaid is converted from native JSON.

## Concurrency

`Egglog.Program` calls against the same handle are safe and isolated. They are
serialized by that one native resource while egglog clones and runs from the
loaded base. Separate `Program` handles are separate native resources.

`Egglog.EGraph` is stateful and uses one owner process for a mutable native
session. Concurrent callers are serialized through normal BEAM message passing.

There is no process-wide NIF mutex and no Elixir worker pool.

## Livebooks

Start at the [notebook index](livebooks/index.livemd) for the full collection.
[Getting Started](livebooks/getting_started.livemd) compares EGraph and Program
using the same arithmetic example, then illustrates queries, native errors and
automatic graph rendering. The index has no runtime or dependencies.

Getting Started uses this checkout locally; a standalone import installs GitHub
`main`. The badge opens the published index, so local changes must be published
before they appear through it. The [shared guide](livebooks/README.md) collects
installation and execution details. The six tutorial chapters retain upstream
prose and order, with automatic Graphviz/Mermaid views throughout.

Then continue with the chapter-by-chapter upstream tutorial adaptations:

* [`livebooks/egglog-tutorial/README.md`](livebooks/egglog-tutorial/README.md)

Those tutorial clones execute the ordinary egglog-language material through the
thin wrapper. Upstream sections that depend on experimental scheduler commands,
dynamic cost models, or Rust-library extension hooks retain their upstream text.
The shared guide explains these boundaries; native graph illustrations accompany
the matrix and compiler examples.

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

Graphviz is optional: default snapshots show SVG when dot is detected, otherwise
Mermaid. Livebook visual examples use this automatic mode. All notebook examples
run through native egglog, and the default Standalone Livebook runtime works.

```sh
mix deps.get
mix test
mix escript.install hex livebook 0.19.10 --force
~/.mix/escripts/livebook server livebooks/index.livemd
```

On Windows, launch Livebook from PowerShell:

```powershell
& "$HOME\.mix\escripts\livebook.bat" server livebooks/index.livemd
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
mix escript.install hex livebook 0.19.10 --force
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
using Livebook's parser, runtime, actual `Mix.install` cells and Kino. The index
imports as navigation-only Markdown.
The compiler chapter includes native schema/expression/rewrite illustrations.
The cell checker also reruns each executable cell consecutively and revisits
early steps after later ones; it checks theory-edit/reload behavior as well as full notebook passes. Graphviz
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

## Graphviz/Mermaid comparison checks

The dev-only comparison tool runs the pinned egraph-serialize 0.3.0 DOT exporter
on the **same JSON** supplied to Mermaid, without reexecuting egglog. The browser
checker uses Kino's bundled Mermaid, verifies rendered labels, directed edges,
argument positions, parallel edges, self-loops, class grouping and type colors,
and can save side-by-side screenshots. It now checks actual arrow-tip positions
against the target class boundary (or member boundary for internal edges), rather
than inferring visual correctness from child IDs. Layout positions are not compared.
Argument-label placement remains Mermaid's default: attempts to set compass ports
produce extra vertices in Kino, and unsupported label-position settings are ignored.

Capture every visual view from all executable library Livebooks and the sibling
course, including consecutive reruns, exercise edits and round selections:

```sh
EGGLOG_GRAPH_PARITY_DIR="$PWD/tmp/livebook-parity" \
  elixir scripts/check_livebook_cells.exs --no-dot
EGGLOG_GRAPH_PARITY_DIR="$PWD/tmp/livebook-parity" \
  elixir ../formal-languages/tutorial/check_cells.exs --no-dot
EGGLOG_MERMAID_EXPORT_DIR="$PWD/tmp/livebook-parity" \
  mix test test/egglog/mermaid_test.exs
CARGO_TARGET_DIR=/tmp/egglog-dot-oracle \
  cargo run --locked --manifest-path scripts/native_graphviz/Cargo.toml -- tmp/livebook-parity
EGGLOG_REQUIRE_DOT_PARITY=1 EGGLOG_MERMAID_SCREENSHOTS="$PWD/tmp/livebook-parity/screenshots" \
  node scripts/check_mermaid_browser.cjs tmp/livebook-parity/kino-assets tmp/livebook-parity
```

Rust, Graphviz and Playwright/Chromium are dev-only requirements for this check.
Set NODE_PATH if Playwright is installed outside the checkout. sources.ndjson
records which notebooks produced each captured graph, including the native
illustrations accompanying the Rust compiler chapter. The exporter restores
non-finite JSON costs (null) to a finite placeholder solely for deserialization; DOT ignores costs.
For a small independent corpus, run `elixir scripts/export_graph_parity.exs`.
