# Known issues

Scope: pinned egglog 3.0.0 revision
`b912caa9694c0c029f9ae3d91db0adc8824e14f5`.
[API_COVERAGE.md](API_COVERAGE.md) records supported functionality and omissions.

## Concurrent execution of clones from one base

**Apparent upstream issue.** A Rust-only probe creates eight clones of a base
containing a `Math` datatype and a rewrite. Each clone concurrently executes
`(let x (Add (Num n) (Num 0)))`, `(run 2)`, and `(extract x)`.
In 80 runs, 68 failed at the current pin and 73 at the previous
`f0da95b0611a7c0be28d89b17e05a11b4490c6b0` pin. Failures included missing
`x` lookups and an `Option::unwrap()` panic in native expression evaluation.
Sequential clones and independently constructed graphs each passed all 80 runs
at both revisions. This checks one workload, not general clone independence.

The wrapper holds a per-program mutex throughout clone execution. Independently
loaded programs can run concurrently; there is no global lock. Caught panics
discard the affected program or mutable graph. The exact upstream cause and
an upstream issue/developer acknowledgment have not been established.

The wrapper regression is `query-local program runs are safe to use concurrently`
in [program_integration_test.exs](test/egglog/program_integration_test.exs).
Remove the execution lock only after upstream clone independence is established
and repeated concurrent tests pass at the replacement pin.

## Precompiled distribution

Normal installs use included, checksum-verified Linux x86-64/ARM64 and Windows
x86-64 bundles. macOS bundles still require matching Mac builders and runners.
Windows validation uses Wine; ARM64 validation uses QEMU. Native hardware and
minimum OS/OTP validation remain release checks. See
[MULTIPLATFORM.md](MULTIPLATFORM.md) for build commands and exact coverage.
No package or release assets have been published.

## Analysis Livebook SVG layout

Graphviz can exceed the rendering deadline while laying out the Analysis
notebook's large graphs. Automatic rendering kills the renderer after 30 seconds
by default and returns native DOT, allowing the lesson to continue. Explicit
`render: :svg` requests return `{:error, {:graphviz_timeout, 30_000}}`;
callers can set `:render_timeout`. All seven notebooks pass the real Livebook
0.19.9 runtime check with this fallback.

DOT/JSON output avoids SVG layout. Native snapshot limits
(`snapshot_max_functions`, `snapshot_max_calls_per_function`) can reduce the
diagram, but the notebook currently requests the full graph. Notebook content
remains unchanged.
