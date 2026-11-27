# Changelog

## v0.3.0

- Inspect bounded, typed table rows on both execution models.
- Opt into native error categories, names and source locations with `error_details: true`.
- Retain matching DOT and JSON in snapshots, rerender without rerunning egglog,
  report Graphviz fallback, and write exports atomically per file.
- Add opt-in structured extraction through `extract_format: :structured`: native
  DAG nodes, roots and exact costs for best terms and variants, including in
  proof mode. Use `Egglog.Extraction.term/2` for nested terms.
- Update egglog 3.0.0 from `b912caa` to `d89bc58` for improvements to extraction,
  parsing, queries and table compaction.
- Install the public Livebooks directly from Hex. Retry native HTTPS downloads
  with system `curl` if available and verify the same pinned checksum.

## v0.2.0

- Remove native archives from Git/Hex. Add a source-bound checksum manifest,
  verified HTTPS downloads, an external cache and explicit offline/source overrides.
  Build outside the checkout; add native five-platform CI, draft-release validation
  and a Hex package size/binary exclusion check.

- Pin native egglog 3.0.0 revision `b912caa9694c0c029f9ae3d91db0adc8824e14f5`.
  Add declaration inspection, typed pattern queries, table clearing and per-graph
  thread configuration.
- Return structured parser spans as `{:error, {reason, message, location}}`.
  Preserve native failed-check categories and report aggregation; validate options
  and return tagged snapshot I/O errors.
- Add JSON-to-Mermaid conversion and exports. Automatic rendering chooses native
  DOT/Graphviz SVG when detected, otherwise JSON/Mermaid. Retain DOT on automatic
  renderer failure; explicit SVG errors remain tagged. Bound Graphviz layout time.
- Preserve DOT graph semantics in Mermaid: native labels/types, class membership,
  ordered arguments, class-boundary targets and exact internal member targets.
  Use standard subgraphs; leave layout to Mermaid. Add native/browser parity checks.
- Add `Program.Step.new/1` and `next/3` as replayable notebook utilities with scoped
  resources. Display retained snapshots through notebook-local Kino integration;
  the library has no Kino dependency.
- Separate the navigation-only index from Getting Started, an application guide
  to EGraph and Program. Keep six upstream tutorial chapters with native graph
  views, including supported matrix/compiler illustrations; retain unsupported
  experimental/Rust material as reference. Put helpers in notebook setup cells.
- Add consecutive cell reruns, earlier-step revisits, disposable Livebook runtime
  checks and browser rendering validation. Keep one canonical improvement backlog.
- Prepare Linux x86-64/ARM64, Windows and macOS native builds. Add installation, relocation and artifact validation.
- Close scoped resources on failure, monitor mutable-session creators, discard
  handles after caught native panics and preserve unexpected server-exit reasons.
  Use dirty scheduling for native operations; remove public typespecs.

## v0.1.0

Initial release.

* Thin Rustler wrapper around native Rust egglog.
* Query-local `Egglog.Program` API for reusable loaded theories.
* Stateful `Egglog.EGraph` API for interactive sessions.
* Raw egglog source execution plus reusable parsed `Egglog.Commands`.
* Checks, extraction, evaluation, function lookup, snapshots, and tuple counts.
* DOT, SVG, and JSON snapshot support.
* Livebook getting-started guide and upstream tutorial adaptations.
