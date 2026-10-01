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

Checksum-verified loading, local packaging and guarded GitHub publication scripts
are implemented. Source builds remain the default until matching artifacts are published. Only
Linux x86_64 GNU is prepared; other targets have not been verified. Publication
requires authenticated GitHub release access and a matching pushed source tag;
neither is supplied by this workspace.

## Analysis Livebook SVG layout

The real Livebook 0.19.9 check of `03-analysis.livemd` cannot finish its first
`Egglog.EGraph.snapshot!/1` SVG rendering cell within the rendering deadline.
Graphviz `dot` remains CPU-bound while laying out the generated 8,745-line DOT
graph. The wrapper now kills the renderer after 30 seconds by default and returns
`{:error, {:graphviz_timeout, 30_000}}`; callers can set `:render_timeout`.
The other six notebooks pass with SVG rendering enabled; later Analysis cells
have not passed this full check.

DOT/JSON output avoids SVG layout. Native snapshot limits
(`snapshot_max_functions`, `snapshot_max_calls_per_function`) can reduce the
diagram, but the notebook currently requests the full graph. No notebook content
was changed to bypass this failure.
