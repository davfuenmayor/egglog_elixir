# Changelog

## Unreleased

* Dirty scheduling for native counting and closing; panic-safe resource handling.
* Creator-monitored mutable sessions and scoped program/graph helpers.
* Native failed-check categories, corrected report aggregation and extraction.
* Validated options and tagged snapshot I/O failures; public typespecs removed.
* API inventory, native build documentation, and opt-in precompiled artifacts.

## v0.1.0

Initial release.

* Thin Rustler wrapper around native Rust egglog.
* Query-local `Egglog.Program` API for reusable loaded theories.
* Stateful `Egglog.EGraph` API for interactive sessions.
* Raw egglog source execution plus reusable parsed `Egglog.Commands`.
* Checks, extraction, evaluation, function lookup, snapshots, and tuple counts.
* DOT, SVG, and JSON snapshot support.
* Livebook getting-started guide and upstream tutorial adaptations.
