# Native bundles

Build with `scripts/build_native.sh`; select a cross target with `EGGLOG_TARGET`.
Archive versions follow the wrapper's Cargo package version. Each `.tar.gz`
contains `native/`: NIF, target identifier, Cargo lockfile, dependency licenses
and any required private runtime library. Keep its SHA-256 sidecar with it.

[Build, test and platform status](../../MULTIPLATFORM.md) distinguishes native
and emulated validation. Only distributable archives/checksums belong here;
intermediate files and logs stay in the external build cache.
