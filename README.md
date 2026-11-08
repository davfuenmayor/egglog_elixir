# EgglogElixir

> **⚠️ Warning:** Install Graphviz (`dot` on PATH) for better-looking graphs. Otherwise Mermaid is used, with less polished layouts.

[![Run in Livebook](https://livebook.dev/badge/v1/blue.svg)](https://livebook.dev/run?url=https%3A%2F%2Fgithub.com%2Fdavfuenmayor%2Fegglog_elixir%2Fblob%2Fmain%2Flivebooks%2Findex.livemd)

Thin Elixir wrapper around native Rust egglog. Reasoning stays in egglog;
the wrapper has no Kino or Livebook dependency.

## Installation and platforms

Requires Elixir 1.19+ and 64-bit Erlang/OTP 27+. Add this checkout to `mix.exs`:

```elixir
{:egglog_elixir, path: "../egglog_elixir"}
```

Checksum-verified NIF bundles cover Linux x86-64/ARM64 (glibc) and Windows x86-64;
normal installation needs no Rust toolchain. macOS requires a source build;
musl/Alpine is unsupported. See [platform status](MULTIPLATFORM.md).

```sh
mix deps.get
mix test
mix escript.install hex livebook 0.19.10 --force
~/.mix/escripts/livebook server livebooks/index.livemd
```

Windows: use `~/.mix/escripts/livebook.bat` from PowerShell. Choose the default
Standalone runtime. First notebook installation needs network access.

For source builds, use `EGGLOG_BUILD=1 mix compile` with Rust/Cargo 1.91+ and a
linker. `scripts/build_native.sh` builds bundles; `EGGLOG_TARGET` selects a target.
`EGGLOG_ELIXIR_BUNDLE` selects an external archive with its `.sha256` sidecar.
Restart the runtime after replacing a NIF. Build/release procedures and coverage
are in [MULTIPLATFORM.md](MULTIPLATFORM.md).

## Execution models

| API | State |
| --- | --- |
| `Egglog.Program` | Each run clones a loaded base; query-local work leaves it unchanged. |
| `Egglog.EGraph` | Calls mutate one session; native push/pop provides checkpoints. |

```elixir
Egglog.Program.with_program("(relation seen (i64))", fn program ->
  Egglog.Program.run!(program, "(seen 1)")
  Egglog.Program.check?(program, "", "(seen 1)") # false: a fresh clone
end)
```

Scoped helpers close handles on success or failure. Return results, not handles.
Calls sharing a handle are serialized; independent handles can run concurrently.
EGraph errors may retain preceding mutations. Caller timeouts do not cancel native
work. Both APIs accept source strings and reusable `Egglog.Commands` values.

`query`, `eval` and `lookup` expose typed values; `extract` returns native term text.
Non-bang functions return tagged results; bang functions raise. Parse errors also
carry source locations: zero-based UTF-8 byte ranges and one-based line/columns.
See module documentation for signatures, options and error contracts.

## Snapshots

```elixir
snapshot = Egglog.Program.snapshot!(program, input, render: :auto)
```

| Render option | Pipeline |
| --- | --- |
| `:auto` (default) | SVG if Graphviz is detected; otherwise Mermaid |
| `:svg` | Native DOT → Graphviz `dot` → SVG |
| `:mermaid` | Native JSON → wrapper converter → Mermaid source |
| `:dot`, `:json` | Native serialization without layout |

Mermaid conversion does not parse DOT. Graphviz discovery checks
`EGGLOG_GRAPHVIZ_DOT`, `GRAPHVIZ_DOT`, then PATH. Overrides name an executable,
without arguments; invalid overrides are ignored. Automatic SVG failure/timeout
retains DOT; explicit SVG requests return an error. `render_timeout` defaults to
30,000 ms and limits Graphviz, not egglog.

SVG snapshots retain `dot`/`svg`; Mermaid snapshots retain `json`/`mermaid`.
Save those fields or request matching artifact paths. `Snapshot.to_mermaid/1`
converts retained JSON without rerunning egglog. Serialization limits and
`snapshot.omitted` describe partial views; they do not bound reasoning work.

Mermaid preserves labelled-graph semantics, including ordered arguments and class
boundaries. Layout differs from Graphviz. In Livebook, display SVG with
`Kino.HTML.new(snapshot.svg)` or Mermaid with `Kino.Mermaid.new(snapshot.mermaid)`.

## Replayable program steps

`Egglog.Program.Step` is a notebook utility over Program, containing accumulated
source and the latest snapshot without retaining a native handle:

```elixir
initial = Egglog.Program.Step.new("(relation seen (i64))")
first = Egglog.Program.Step.next(initial, "(seen 1)", render: :auto)
```

Each step replays preceding source; earlier steps remain unchanged. Notebook setup
provides automatic Kino display. See the [Livebook guide](livebooks/README.md#execution-and-revisiting-cells).

## Livebooks

- [Index](livebooks/index.livemd): all notebooks; also the launch-badge target.
- [Getting Started](livebooks/getting_started.livemd): application usage of both models, queries and error recovery.
- [Tutorial chapters](livebooks/egglog-tutorial/README.md): upstream egglog lessons.
- [Setup and scope](livebooks/README.md): notebook conventions and extension boundaries.

Getting Started installs this checkout locally or GitHub `main` on standalone
import. The badge uses published GitHub content; local edits require publication.

## Livebook checks

From the project root:

```sh
mix test
mix docs --warnings-as-errors
elixir scripts/check_livebook_cells.exs
elixir scripts/check_livebook_cells.exs --no-dot
```

The cell checker reruns cells and revisits earlier steps. For real Livebook/Kino
checks, start a separate server, then run the checker from another shell:

```sh
epmd -daemon
LIVEBOOK_IFRAME_PORT=8192 ~/.mix/escripts/livebook server --ip 127.0.0.1 --port 8191 \
  --name egglog_livebooks@127.0.0.1 --cookie YOUR_LOCAL_COOKIE
```

```sh
elixir --name egglog_checker@127.0.0.1 --cookie YOUR_LOCAL_COOKIE \
  scripts/check_livebooks.exs egglog_livebooks@127.0.0.1
```

Append notebook paths to select files. Sessions evaluate disposable copies;
the index imports without execution.

## Graphviz/Mermaid comparison checks

Use a fresh corpus directory. The native DOT oracle and browser checker compare
representations of the same retained JSON, including labels, argument order,
class grouping and arrowhead targets. Playwright/Chromium are dev dependencies.

```sh
npm install --prefix /tmp/egglog-browser playwright
/tmp/egglog-browser/node_modules/.bin/playwright install --with-deps chromium
EGGLOG_GRAPH_PARITY_DIR="$PWD/tmp/parity" \
  elixir scripts/check_livebook_cells.exs --no-dot
CARGO_TARGET_DIR=/tmp/egglog-dot-oracle \
  cargo run --locked --manifest-path scripts/native_graphviz/Cargo.toml -- tmp/parity
NODE_PATH=/tmp/egglog-browser/node_modules EGGLOG_REQUIRE_DOT_PARITY=1 \
  node scripts/check_mermaid_browser.cjs tmp/parity/kino-assets tmp/parity
```

Set `EGGLOG_MERMAID_SCREENSHOTS` for comparison screenshots. Native identifiers
and layout can vary across runs; counts alone do not establish graph equivalence.

## Reference

[API coverage](API_COVERAGE.md) · [Known issues](KNOWN_ISSUES.md) ·
[Changelog](CHANGELOG.md) · [Upstream](https://github.com/egraphs-good/egglog)
