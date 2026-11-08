# Native builds and testing

The wrapper targets egglog 3.0.0 at the Git revision pinned in
`native/egglog_nif/Cargo.toml` and `Cargo.lock`. Rustler supplies the native NIF
boundary; a Mix compiler installs a checksum-verified local platform bundle.
The Elixir loader uses the standard NIF API and native Windows path separators.
No Elixir-side Rustler/compiler dependency is needed for a binary installation.
Normal installs do not invoke Cargo or contact GitHub releases.

## Platform status

| Target | Build and validation |
| --- | --- |
| Linux x86-64, glibc | Included; 109 checks and documentation generation pass on Linux |
| Linux ARM64, glibc | Included; rebuilt for structured parse diagnostics; runtime revalidation pending (previous revision: 78 checks under QEMU) |
| Windows x86-64 | Included; rebuilt for structured parse diagnostics; runtime revalidation pending (previous revision: 75 checks under Wine) |
| macOS Intel | Native recipe prepared; Mac runner required |
| macOS Apple Silicon | Native recipe prepared; Mac runner required |

Only included, tested bundles provide an installation without build tools.
Native macOS validation is unavailable in this Linux container. musl/Alpine,
32-bit BEAM and Windows ARM64 are excluded. Match the running BEAM's CPU;
an Intel BEAM under Rosetta needs the Intel bundle.

Linux bundles require **glibc 2.35+**: the NIF itself needs 2.34, and its bundled
GCC unwinder needs 2.35. Runtime checks here use glibc 2.41. Windows 10+ and
macOS 12+ are intended baselines; native/minimum-version validation is pending.

## Build

Use Rust/Cargo 1.91+, a platform linker, Bash, tar, Elixir 1.19+ and 64-bit OTP
27+. On Debian/Ubuntu install `build-essential patchelf`; ARM cross-builds also
need `gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu`, and Windows cross-builds
need the POSIX MinGW-w64 GCC/binutils tools. Add Rust's target standard libraries
with `rustup target add aarch64-unknown-linux-gnu x86_64-pc-windows-gnu`.
The builder copies Rust's standard-library notices from the toolchain; install
`rustup component add rust-docs` if using a minimal Rust installation.

```sh
scripts/build_native.sh
EGGLOG_TARGET=linux-aarch64 scripts/build_native.sh
EGGLOG_TARGET=windows-x86_64 scripts/build_native.sh
```

The first command builds the native host. Cross-build commands above run on
Linux x86-64. The locked Rust dependency tree needs no OpenSSL or C++ runtime.
Linux bundles include private `libgcc_s` with a relative loader path; Windows
uses a static CRT and rejects MinGW runtime DLL imports.

For macOS, install Xcode Command Line Tools and native Rust/Elixir, then run
`scripts/build_native.sh` on each architecture. The script defaults to a macOS
12 deployment target, strips the dylib and ad-hoc signs it. Check `otool -L`
and run the tests on both Macs before claiming support.

For native Windows, use 64-bit Rust MSVC with Visual Studio Build Tools, or
Rust GNU with the POSIX MinGW toolchain. Run the builder in Git Bash with the
matching linker on `PATH`. Native Windows recipes still need a Windows runner;
Wine validation does not replace that check.

Archives and SHA-256 sidecars go into `native/precompiled/`. Each contains
`native/` with the NIF, target identifier, Cargo lockfile and third-party license
notices. Build trees, metadata, test copies and logs stay under
`${XDG_CACHE_HOME:-$HOME/.cache}/egglog-elixir`, outside the repo. Override with
`EGGLOG_BUILD_ROOT`; `BUILD_JOBS=4` controls compilation parallelism.

## Bring your own binaries

Build on your machine, then run `mix compile`. The API and notebook setup are
identical. `EGGLOG_BUILD=1 mix compile` explicitly invokes the builder;
`config :egglog_elixir, build_from_source: true` remains available, as does the
legacy `RUSTLER_PRECOMPILED_FORCE_BUILD_ALL=true` environment flag.

Set `EGGLOG_ELIXIR_BUNDLE` to an external archive's absolute path and keep its
`.sha256` beside it. In Windows PowerShell:

```powershell
$env:EGGLOG_ELIXIR_BUNDLE = 'C:\bundles\egglog-0.2.0-windows-x86_64.tar.gz'
mix compile
```

Native builds can use `RUSTFLAGS='-C target-cpu=native'` for local tuning; do not
redistribute CPU-specific bundles to other machines. Benchmark improvements
and rerun tests. Restart BEAM/Livebook after changing a loaded NIF.

Publication is separate from installation. After an explicit release request,
commit reviewed artifacts, tag that commit as `v0.2.0`, and run
`MIX_ENV=prod mix run scripts/publish_native.exs` with authenticated GitHub CLI.
The script verifies the clean tagged source and hashes and refuses replacement
of an existing release. Builds and notebooks never publish anything.

For local upstream experiments, add a temporary Cargo Git-source patch to
`native/egglog_nif/Cargo.toml`, update its lockfile, and rebuild from source.
Restore the pin/lockfile before distribution.

## Test

```sh
mix deps.get
mix test
elixir scripts/check_livebook_cells.exs
```

Run installation and relocation checks with Cargo absent from `PATH`. The
bundle tests reject checksum, target and payload errors and restore missing
native files. A fresh VM loads an app moved to a path containing spaces and
executes both mutable e-graph and isolated program queries plus JSON snapshots.
The cell checker evaluates the seven executable notebooks twice and recognizes
the navigation-only index. Real Livebook parser/runtime checks use disposable
copies to protect sources from autosave; commands are in README.md.

Graphviz is optional. Without `dot`, automatic snapshots return JSON-derived
Mermaid; explicit DOT/JSON outputs remain available. Automatic rendering also returns native DOT if Graphviz
fails or times out; explicit `render: :svg` retains renderer errors. Check both the
Graphviz-enabled workflow and the default fallback without changing lessons.

`elixir scripts/check_livebook_cells.exs --no-dot` clears `PATH` after dependency
setup, exercising every lesson twice without Graphviz or runtime build tools.

For every architecture, inspect native dependencies using `ldd` / `readelf`,
`otool -L`, or `objdump -p` / `dumpbin /DEPENDENTS`. Test the oldest claimed OS,
minimum/current OTP, a fresh dependency installation and relocation. Record
emulated checks separately from native hardware. Check package size with
`mix hex.build` before publication.

## Remaining release checks

- Build and validate Intel/Apple Silicon archives on matching Macs.
- Repeat Windows and ARM64 checks on native hardware and supported OS baselines.
- Validate the three POSIX renderer probes with native Windows equivalents and
  a real Windows Graphviz installation, including timeout/process cleanup.
- Verify minimum glibc/macOS/Windows and OTP versions on real target runtimes.
- Check redistribution notices for native MSVC/MSYS2 and macOS builds; included
  bundles already carry crate, Rust standard-library and GCC/MinGW notices.
- Recheck complete package size after adding macOS artifacts; if it exceeds
  the package host's limit, release assets need hosting and download support.
- Tagging/publication and testing the publishing script against a real release
  require an explicit release request.

## Validation evidence

Linux checks use Elixir 1.20.4, OTP 29.1.1 and Debian 13/glibc 2.41. Current local
coverage is 109 ExUnit checks, documentation generation, cell reruns with both
automatic renderer paths, and Livebook 0.19.10 imports/execution of seven notebooks
plus a navigation-only index (111 executable cells). These notebooks have not been
revalidated on Windows or ARM64 after the current revisions.

Older platform checks, before the structured-parser bundle refresh:

| Runtime | Recorded evidence | Limit |
| --- | --- | --- |
| Windows/Wine 10 | 75 checks, Windows DLL loading, dependency compilation and relocation | Three POSIX renderer probes skipped; no native Windows hardware check |
| ARM64/QEMU | 78 checks including a targeted installation-regression rerun; native smoke check | Emulated BEAM/NIF; no native ARM hardware check |

The package was previously built locally (about 8.9 MiB, three bundles), unpacked,
and exercised with an empty PATH. This checked both APIs, snapshots and relocation,
not publication or the latest notebook contents. Native dependency inspection found
private `libgcc_s`, glibc/libm on Linux and only system DLL imports on Windows.

Emulation roots and logs remain outside the repository. The ARM test launcher uses
host launch utilities around an ARM64 BEAM/NIF under QEMU, not a native/full-system
installation. Current payload revalidation and oldest-platform tests remain open
in the platform table and release checklist above.
