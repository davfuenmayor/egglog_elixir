# Changelog

## Unreleased (0.2.0)

* Separate the navigation-only `index.livemd` from Getting Started, an application
  guide to EGraph/Program, typed queries, failure recovery, ownership and rendering.
  Point the README launch badge and all back-to-index links at the index.

* Keep dependencies, display helpers and rendering options together in each
  Livebook setup cell, with a short setup note before the lesson.

* Make Getting Started a collection index and concise two-model library tour.
  Showcase the same arithmetic example with EGraph checkpoints/rollback and
  independent Program runs, with automatic graphs throughout. Keep Step as a
  briefly mentioned notebook utility.
  Add a Run in Livebook badge; preserve the original notebook path for navigation.

* Add `Egglog.Program.Step.new/1` and `next/3` for replayable source/snapshot
  values with scoped native resources. Convert tutorial examples to
  `step = next.(previous, code)` and automatically display native output and
  graphs through a notebook-local Kino protocol, without a library Kino dependency.

* Restore upstream tutorial prose throughout all seven Livebooks, with MIT
  attribution. Centralize wrapper/runtime guidance in the Livebook README.
  Show 106 automatic Graphviz/Mermaid snapshots, replacing summary-only cells
  and exposing intermediate states, checks, extraction and rollback. Add native
  graph illustrations for the matrix and compiler case studies while retaining
  the upstream experimental/Rust reference material.

* Simplify Mermaid rendering to one class/subgraph and constructor/node model.
  Remove custom singleton HTML, its separate escaping path and backslash-span
  workaround. Retain DOT class-boundary targets, internal member targets, ordered
  arguments, native labels/types, sharing and cycles. Leave sizing to Mermaid.

* Correct visible Mermaid arrowheads to follow DOT lhead class boundaries, retaining
  exact member targets for internal edges. Pack singleton classes tightly around
  their constructors, reduce spacing/font overhead, and omit unary zero labels.
  Check actual rendered arrow-tip coordinates against native DOT target boxes.

* Align Mermaid with native DOT's labelled graph: remove synthetic equality
  anchors, preserve exact e-node child references, match class metadata labels,
  type colors, rounded nodes and dashed class styling. Preserve ordered edges,
  repeats and cycles. Add native-exporter/browser parity checks and screenshots
  for every visual Livebook view; document unavoidable layout differences.

* Automatic snapshot rendering now selects Graphviz SVG when dot is detected
  (EGGLOG_GRAPHVIZ_DOT, GRAPHVIZ_DOT, or PATH), otherwise JSON/Mermaid.
  Preserve native DOT on a detected renderer's failure/timeout. All executable
  library Livebooks use automatic visual views and retain omission notices.

* Preserve native parser source spans as `{:error, {reason, message, location}}`
  across parsing, loading, running and inspection, including included files.
  Locations expose UTF-8 byte ranges and line/column coordinates without
  parsing diagnostic text. Non-parser error shapes remain unchanged.

* Make notebook experiments revisitable with explicit source baselines and scoped
  Program queries, including snapshots before and after native push/pop.
* Centralize onboarding/lifecycle/limit guidance, correct navigation and remove
  hypothetical package advice; explain experimental/Rust extension boundaries.
* Test consecutive cell reruns, early-step revisits, closed handles and theory
  edits/reloads; add before/one/two rounds and negative-remainder examples.

* JSON-to-Mermaid snapshots with render: :mermaid, mermaid_path exports, and
  Snapshot.to_mermaid/1 for existing JSON. Preserves classes, ordered
  class-targeted edges, aliases and metadata without Graphviz.
* Livebook visual examples use Kino.Mermaid; the Analysis views show explicit
  omission notices for capped views.

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
