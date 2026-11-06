# Improvements for AI-agent workflows

These suggestions come from exercising the actual Livebooks, automatic rendering,
structured parse errors, and Graphviz/Mermaid comparison tooling. They are proposals,
not claims that these APIs already exist. Priorities favor inspectable native data,
explicit lifecycle semantics, and reproducible results.

## Current strengths to preserve

- Program queries clone a loaded base; scoped helpers make independent experiments
  safe to rerun. EGraph deliberately accumulates mutation and supports push/pop.
  This distinction works; it does not need an implicit reset/replay mechanism.
- Parse errors already carry structured native source spans. Mermaid already comes
  from JSON, and automatic rendering already discovers Graphviz or selects Mermaid.
- Displaying retained results need not execute egglog again. Keep this separation.

## P1: Export multiple views from one native serialization

**Problem observed:** A visual snapshot contains DOT/SVG or JSON/Mermaid according
to renderer discovery. Comparing both requires either another serialization or a
dev-only Rust oracle. An agent should not need to reconstruct an experiment merely
to inspect a different format.

**Proposal:** Allow paired native JSON/DOT exports from one serialized object, then
convert/render those retained representations. Include native revision and serializer
version. This can be an opt-in option to avoid extra work for ordinary calls.

**Acceptance:** One native execution and one serialization produce all requested
representations, with identical node IDs, children, classes, caps and omission
metadata. A mutable session is never advanced to produce another view. Renderer
failures preserve the other representations and the original execution result.

## P1: Return rendering decisions and fallback diagnostics as data

**Problem observed:** Automatic rendering can succeed as a wrapper call while a
Graphviz failure produces raw DOT. The reason is then unavailable to the caller.
An agent cannot distinguish an unavailable renderer from a crashed or timed-out one
merely by inspecting a successful result's format.

**Proposal:** Include a rendering report, separate from the native run report:
requested/selected format, resolved executable, discovery source, elapsed layout
time, warnings, and any fallback reason. Retain renderer stderr and exit status.
Keep explicit :svg errors and successful native execution distinguishable.

**Acceptance:** Missing binary, invalid override, nonzero exit and timeout have
stable machine-readable codes. Executable discovery alone never claims that a
renderer works. Reading this report triggers no native run or capability probe.

## P1: Add an artifact manifest and prevent stale-file confusion

**Problem observed:** Switching an experiment from Mermaid to SVG leaves previous
.mmd/.json files beside new .dot/.svg files. A directory scan can pair old files
with a current result, even though the notebook itself correctly uses saved data.

**Proposal:** Return/write a per-export manifest listing only files produced by
that call, content hashes, source snapshot hash, native version, selected renderer,
and omission metadata. Write files atomically. Do not delete arbitrary neighboring
files; an explicit managed-export directory may support controlled cleanup.

**Acceptance:** An agent can select the exact current artifacts from the manifest,
without inferring freshness from filenames, timestamps, or a glob. Interrupted
writes cannot leave a partially updated manifest claiming success.

## P1: Extend structured diagnostics beyond parsing

**Problem observed:** Parse locations are useful, but many type, lookup, ruleset,
and execution errors still share :native_error plus human-readable text. Generated
request prefixes also make a native source offset different from an input-field
offset. Mutable command batches may retain earlier successful changes on error.

**Proposal:** Preserve structured native error kinds and available spans for these
errors, including multiple type diagnostics. Where wrapper-generated source is
used, optionally return that exact source and a source map to input fields. Expose
execution/parse stage and whether mutation may already have occurred; do not imply
rollback when the native API provides none.

**Acceptance:** Agents can classify a type mismatch without parsing its message,
locate the relevant source, and distinguish malformed input from a failed check.
The full native message remains available. Unavailable spans/progress are marked
unknown rather than inferred. Preserve the Program/EGraph lifecycle contract.

## P2: Provide a small, versioned capability report

**Proposal:** Expose native egglog revision, serializer schema/version, enabled
features, supported snapshot formats, and resolved renderer availability through a
public read-only function. Distinguish executable discovery from an opt-in smoke
probe. Document precedence and source coordinates in machine-friendly examples.

**Why useful:** An agent can choose a supported operation and explain environmental
failures before starting a long experiment. Currently it must inspect internal
modules, documentation, or platform bundles for parts of this information.

## P2: Make snapshot comparison explicit and honest

**Problem observed:** Native IDs, chosen child representatives, class ordering and
layout can differ between independent serializations. Equal node/class counts do
not prove equal graphs or successful derivation. Within one snapshot, exact child
references and ordered edges are valuable evidence.

**Proposal:** Offer labelled-graph inspection/comparison helpers with explicit
modes: exact native identity; comparison under a supplied ID mapping; and comparison
by stable aliases plus child classes. Report unmatched or ambiguous mappings.
Keep a raw content hash for artifact integrity, distinct from semantic comparison.

**Acceptance:** Repeated edges, argument order, sorts, aliases and cycles are checked.
No helper claims semantic equivalence from counts, extraction text, or layout.
Do not promise a trivial canonical hash for arbitrary cyclic graphs; define any
canonicalization and its limits before implementing it.

## P2: Expose structured extraction results when supported upstream

**Proposal:** Return native extraction terms/ASTs and costs alongside display text,
when the upstream API supplies them. Include whether an extraction was truncated.

**Why useful:** Agents can inspect a constructor and its ordered arguments directly,
without reparsing a pretty-printed expression. Preserve original extraction text
and native choices; avoid introducing a second egglog parser or simplifier.

## P2: Consolidate the notebook validation interface

**Problem observed:** The comparison currently combines separate code-only,
Livebook-runtime, capture, native-DOT and browser tools. Course controls require
explicit input defaults/overrides, while no-Graphviz checks isolate PATH.

**Proposal:** Add a documented dev runner with notebook selection, renderer scenarios,
input overrides, captured artifacts, provenance, and a JSON result report. Run
environment-dependent cases in isolated processes. Keep examples in the notebooks
and read them during validation; do not create competing lesson implementations.

**Acceptance:** The runner records exact notebook inputs, checks both automatic
renderer branches, revisits earlier phases, and reports browser rendering separately
from creation of a Kino object. It preserves the explicit difference between fresh
Program experiments and sequential EGraph operations, and never autosaves over
an authoritative notebook during validation.

## Additional lesson: distinguish stored edges from visible arrowheads

The boundary correction showed that equality of serialized child IDs does not
establish Graphviz visual fidelity. DOT lhead clips cross-class edges to class
boxes; source tail ports also carry argument order. The comparison now checks
actual rendered arrow-tip coordinates. A useful future render contract should
expose source constructor, argument index, target class, native representative,
and clipping policy separately. Publish renderer limitations by version so agents
do not assume that a parsed configuration option actually changed the output.
