# Important outstanding improvements

Status updated 2026-11-15 against wrapper revision
`e95b09d1841e4e48af109ef08ee50c5e9933a503` (0.2.0), plus the local migration.
This is the sole improvement backlog for EgglogElixir; only missing, high-value
work is listed.
Source review does not constitute new platform or release validation.

## P0: Validate and publish the native platform matrix

The native CI workflow now covers both Macs, Linux x86-64/ARM64 and Windows with
minimum/current BEAM versions, but remote runs and Mac artifacts remain pending.
Review actual native results, dependency inspections, OS baselines and the complete
five-target checksum/provenance manifest. Compiler-free Mac installation is not yet
a delivered capability. Pin the course only after the release passes installation.

## P0: Finish release-download migration before Hex publication

Tracked binaries have been removed; verified downloads, external caching, offline
overrides, source builds and size checks are implemented. Existing checksums were
imported into the manifest. The remaining work is to run native CI, review the
artifacts, publish immutable release assets, and test anonymous cold-cache Git and
Hex installs on each promised platform. The publisher prepares a draft only.
Do not publish Hex while its required native assets are unavailable. Release steps
are in [MULTIPLATFORM.md](MAINTAINING.md).

## P1: Export consistent views from one native snapshot

`native/egglog_nif/src/snapshot.rs` exports only DOT or JSON per request. Add an
opt-in paired export from one execution and one serialized object, deriving SVG
from retained DOT and Mermaid from retained JSON.

**Done when:** requested views share node IDs, ordered children, classes, limits
and omission metadata. Switching views never reruns source or advances a mutable
graph. Rendering failure preserves the native result and other representations.

## P1: Preserve rendering diagnostics

Automatic SVG fallback in `lib/egglog/common.ex` drops the Graphviz error. Return
the selected renderer/executable, warnings and a structured fallback reason,
including exit status/output or timeout. Preserve explicit SVG error behavior.

**Done when:** callers can explain missing executables, failed overrides, nonzero
exits and timeouts from returned data. Discovery is not reported as a successful
renderer probe, and reading diagnostics causes no hidden execution.

## P1: Make artifact exports reliable

Artifact writes in `lib/egglog/common.ex` use direct `File.write`; failed writes
or renderer changes can leave mixed old/new files. Write atomically, report only
artifacts produced by that call, and report unavailable requested formats.
For multi-file exports, use an explicit commit boundary such as an immutable
export directory or a manifest published last with matching content hashes.

**Done when:** interrupted writes cannot advertise a complete inconsistent set;
consumers need no globs or timestamps to identify current artifacts. Never delete
arbitrary neighboring files or imply native rollback after an export failure.

## P1: Preserve structured non-parser errors

`native/egglog_nif/src/error.rs` stringifies most type, name/ruleset lookup and
execution errors. Preserve native categories and available spans alongside the
full message. Identify the failure stage and which source coordinates apply;
expose generated request source when needed to make diagnostics actionable.

**Done when:** callers classify errors without parsing English messages. Missing
spans or mutation progress remain unknown; errors never imply unsupported rollback.
Evolve the existing error contract without silently breaking callers.

## P2: Investigate genuine native execution limits

Caller timeouts, output limits and snapshot caps do not stop or bound native
reasoning. Check upstream support for cooperative cancellation or resource limits
before choosing an API. If hard termination needs process isolation, evaluate it
separately and define handle state and partial-mutation behavior.

**Done when:** any advertised deadline or budget actually stops or bounds native
work. Until feasible, retain the limitation in [KNOWN_ISSUES.md](KNOWN_ISSUES.md)
rather than adding a misleading timeout option.
