# Egglog tutorial chapters

Read [installation, execution contracts and limits](../README.md) first.
These chapters adapt the upstream native-language tutorial to the thin Elixir wrapper.

| Chapter | Status | Main lesson |
| --- | --- | --- |
| [01 — Equality Saturation](01-basics.livemd) | Executable Program phases | Signatures, terms, congruence, rounds, extraction |
| [02 — Datalog](02-datalog.livemd) | Executable Program phases | Relations, shortest paths, equality and facts, native rollback |
| [03 — E-class Analysis](03-analysis.livemd) | Executable Program phases | Derived facts and guarded rewrites |
| [04 — Scheduling](04-scheduling.livemd) | Executable native schedules; marked experimental sections reference-only | Rulesets, run/repeat/saturate |
| [05 — Extraction and Cost](05-cost-model-and-extraction.livemd) | Static costs executable; dynamic-cost sections reference-only | Representative selection and cost |
| [06 — LA compiler](06-case-study.livemd) | Reference only; no executable cells | Rust embedding and native extension hooks |

The native examples remain visible in their teaching order. Each executable
phase reconstructs its explicitly named immutable source baseline, uses
Program.with_program/run!, and returns ordinary data after closing the handle.
Views reconstruct the phase they name; they do not inspect a hidden mutable graph.
Evaluate preceding definitions before dependents, and reevaluate dependents after
edits. See [Getting Started](../getting_started.livemd) for intentional sequential
EGraph accumulation and push/pop inside a scoped cell.

Mermaid views run in Kino and require no Graphviz. Partial Analysis views display
native omission metadata. Helpers only display returned snapshots/output; they do
not synthesize check results or implement equality reasoning.

## Native extension boundary

Standard datatype/relation/rule commands, rulesets, schedules and static
constructor costs are executable. Experimental back-off/custom schedulers,
dynamic cost models and Rust extension hooks are explicitly marked reading
material. Chapter 06 describes an upstream Rust compiler; it does not implement
that compiler in Elixir. No new wrapper reset, scheduler or reasoning engine is
needed for the phase-based notebook execution.
