# Known issues

Scope: pinned egglog 3.0.0 revision
`b912caa9694c0c029f9ae3d91db0adc8824e14f5`.
Reviewed 2026-11-08 against the current working tree.
Only outstanding issues and limitations are listed here.
[API_COVERAGE.md](API_COVERAGE.md) records supported functionality and omissions.
Open API proposals are in [egglog_elixir_improvements.md](egglog_elixir_improvements.md).

## Precompiled distribution gaps

macOS bundles still require matching Mac builders and runners. Windows validation
uses Wine; ARM64 validation uses QEMU. Native hardware and minimum OS/OTP
validation remain release checks. See [MULTIPLATFORM.md](MULTIPLATFORM.md) for
build commands and exact coverage.

## Automatic fallback loses renderer diagnostics

`lib/egglog/common.ex` returns a successful DOT snapshot after an automatic SVG
failure/timeout, but drops the renderer error. The snapshot's format identifies
the fallback, not its cause. A rendering report remains an open proposal in
[egglog_elixir_improvements.md](egglog_elixir_improvements.md).

## Mermaid layout fidelity

Mermaid cannot reproduce DOT source ports, edge-label positions, box proportions
or routing exactly. Graphviz remains the layout reference. These presentation
limitations prevent identical appearance even for the same labelled graph.

## Native execution cancellation and resource budgets

Caller timeouts do not cancel native computation. Output limits truncate returned
output, and snapshot caps limit serialization; neither bounds reasoning work.
A run count is not a general native time or memory budget. The wrapper provides
no native cancellation or general execution deadline.
