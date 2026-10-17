# Changelog

## Unreleased (0.2.0)

* Pin egglog 3.0.0 revision `b912caa9694c0c029f9ae3d91db0adc8824e14f5`.
* Native declaration inspection, pattern queries, and mutable table clearing.
* Per-graph thread configuration, including load-time settings retained by clones.
* Discard program bases after caught panics; preserve unexpected server exit reasons.
* Request helpers consistently normalize string-key inputs before appending requests.
* Bundle checksum-verified Linux x86-64/ARM64 and Windows x86-64 native builds;
  normal installation needs no Rust toolchain. Add native macOS build recipes.
* Bound SVG rendering with `:render_timeout` and terminate Graphviz on expiration.
* Fall back to native DOT when automatic SVG rendering fails or times out.
* Share native output display helpers; remove source-derived check messages from Livebooks.

* Dirty scheduling for native counting and closing; panic-safe resource handling.
* Creator-monitored mutable sessions and scoped program/graph helpers.
* Native failed-check categories, corrected report aggregation and extraction.
* Validated options and tagged snapshot I/O failures; public typespecs removed.
* API inventory and multiplatform native build/test documentation.

## v0.1.0

Initial release.

* Thin Rustler wrapper around native Rust egglog.
* Query-local `Egglog.Program` API for reusable loaded theories.
* Stateful `Egglog.EGraph` API for interactive sessions.
* Raw egglog source execution plus reusable parsed `Egglog.Commands`.
* Checks, extraction, evaluation, function lookup, snapshots, and tuple counts.
* DOT, SVG, and JSON snapshot support.
* Livebook getting-started guide and upstream tutorial adaptations.
