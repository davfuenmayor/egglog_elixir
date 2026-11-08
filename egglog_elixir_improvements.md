# Improvements for AI-agent workflows

These suggestions come from exercising the actual Livebooks, automatic rendering,
structured parse errors, and Graphviz/Mermaid comparison tooling. They are proposals,
not claims that these APIs already exist. Priorities favor inspectable native data,
explicit lifecycle semantics, and reproducible results.

Review: 2026-11-08, against the current working tree (including the Step helper,
index/application-guide split, and simplified Mermaid renderer). This is a code
and recorded-validation review, not a new upstream, release or platform audit.
Current limitations are tracked in [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

Only outstanding proposals are listed below. Existing dev tools are mentioned
only where they can support implementation of an open proposal.

## P1: Export multiple views from one native serialization

**Problem observed:** A visual snapshot contains DOT/SVG or JSON/Mermaid according
to renderer discovery. Comparing both requires either another serialization or a
dev-only Rust oracle. An agent should not need to reconstruct an experiment merely
to inspect a different format.

`native/egglog_nif/src/snapshot.rs` exports only one selected format per snapshot.
The public paired-export API is missing. Reuse `scripts/native_graphviz` as a
reference for deriving native DOT from retained JSON.

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
The selected format identifies the path taken, but does not explain a renderer
failure or why a discovery override was skipped. Automatic DOT fallback discards
the renderer error in `lib/egglog/common.ex`.

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

Public artifact writes in `lib/egglog/common.ex` use direct `File.write`, without
a manifest or atomic group commit. Unavailable format-specific artifacts yield nil paths;
these should be reported explicitly rather than inferred from neighboring files.

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

Non-parser type and execution details are generally stringified in
`native/egglog_nif/src/error.rs`. Structured kinds, additional spans and source
mapping for these diagnostics remain missing.

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

There is no single public, versioned capability report.

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

A public cross-snapshot comparison API with explicit identity/mapping semantics
is missing. Reuse `scripts/check_mermaid_browser.cjs` as a reference for labelled
graph checks, without treating its within-snapshot parity checks as cross-run matching.

**Proposal:** Offer labelled-graph inspection/comparison helpers with explicit
modes: exact native identity; comparison under a supplied ID mapping; and comparison
by stable aliases plus child classes. Report unmatched or ambiguous mappings.
Keep a raw content hash for artifact integrity, distinct from semantic comparison.

**Acceptance:** Repeated edges, argument order, sorts, aliases and cycles are checked.
No helper claims semantic equivalence from counts, extraction text, or layout.
Do not promise a trivial canonical hash for arbitrary cyclic graphs; define any
canonicalization and its limits before implementing it.

## P2: Expose structured extraction results when supported upstream

Native command outputs in `native/egglog_nif/src/run.rs` and the public extraction
helpers return extraction text rather than a structured compound term and cost.

**Proposal:** Return native extraction terms/ASTs and costs alongside display text,
when the upstream API supplies them. Include whether an extraction was truncated.

**Why useful:** Agents can inspect a constructor and its ordered arguments directly,
without reparsing a pretty-printed expression. Preserve original extraction text
and native choices; avoid introducing a second egglog parser or simplifier.

## P2: Consolidate the notebook validation interface

**Problem observed:** Validation combines separate code-only, Livebook-runtime,
capture, native-DOT and browser tools. There is no unified runner or JSON report
covering selection, renderer scenarios, replay and browser output. Input overrides
also need a consistent interface for notebooks that use controls.

**Proposal:** Add a documented dev runner with notebook selection, renderer scenarios,
input overrides, captured artifacts, provenance, and a JSON result report. Run
environment-dependent cases in isolated processes. Keep examples in the notebooks
and read them during validation; do not create competing lesson implementations.

**Acceptance:** The runner records exact notebook inputs, checks both automatic
renderer branches, revisits earlier steps, and reports browser rendering separately
from creation of a Kino object. It preserves the explicit difference between fresh
Program experiments and sequential EGraph operations, and never autosaves over
an authoritative notebook during validation.

## P2: Publish a versioned rendering contract

**Proposal:** Expose source constructor, argument index, target class, native
representative and clipping policy separately. Publish renderer limitations by
version so agents can distinguish labelled-graph semantics from layout differences.

**Acceptance:** Consumers can tell which endpoints and ordered arguments are
represented without inferring them from arrow geometry or layout configuration.
