# Known issues

Scope: pinned egglog revision `f0da95b0611a7c0be28d89b17e05a11b4490c6b0`.
[API_COVERAGE.md](API_COVERAGE.md) records supported functionality and omissions.

## Concurrent execution of clones from one base

**Apparent upstream issue; observed during this wrapper refactor.** Releasing the
program mutex after cloning caused the existing concurrent-program integration
test to fail repeatedly. Observed failures included missing `x` lookups and a
caught panic at upstream `src/lib.rs:1275` (`Option::unwrap()` on `None`).

A standalone Rust probe using the same dependency pin and lockfile also failed:
eight clones were created from one base and started together behind a barrier,
each running `(let x (Add (Num n) (Num 0)))`, `(run 2)`, and `(extract x)`.
Seven of eight runs failed, including the same upstream panic. No Elixir code
or wrapper resource was involved.

Repeated Rust-only checks (80 runs per case) found 73 concurrent-clone failures
at the pinned revision and 68 at cloned revision
`b912caa9694c0c029f9ae3d91db0adc8824e14f5`. Sequential clones and independently
constructed graphs each passed all 80 runs at both revisions. These checks
exercise the small program above, not every possible workload.

The wrapper therefore retains its per-program mutex throughout clone-local
execution. Independently loaded program handles can run concurrently. There is
no global lock. Panics are caught inside the guarded scope so unwinding does not poison
that mutex. No upstream issue or developer acknowledgment has been verified;
the exact upstream cause has not been established.

The regression is `query-local program runs are safe to use concurrently` in
[test/egglog/program_integration_test.exs](test/egglog/program_integration_test.exs).
Remove the execution lock only after upstream clone independence is established
and repeated concurrent runs pass against the newly pinned revision.

## Precompiled distribution

Checksum-verified loading and a local release-packaging script are implemented.
Source builds remain the default until matching artifacts are published. Only
Linux x86_64 GNU is prepared; other targets have not been verified. No release
was uploaded by this change.
