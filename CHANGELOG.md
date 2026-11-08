# Changelog

## Unreleased (0.2.0)

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
- Bundle checksum-verified Linux x86-64/ARM64 and Windows x86-64 native builds;
  prepare macOS recipes. Add installation, relocation and artifact validation.
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
