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
| Linux x86-64, glibc | Included; 78 checks passed, all seven actual Livebook runtimes passed |
| Linux ARM64, glibc | Included; 78 checks validated under QEMU, all seven notebook cell checks passed |
| Windows x86-64 | Included; 75 checks passed under Wine, three POSIX renderer probes skipped |
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

The previous opt-in RustlerPrecompiled URL/checksum workflow is replaced by
complete local bundles. No unpublished release URL is needed for installation.
The publishing script verifies reviewed archives and checksums, but is never
run by a build or notebook. No release assets have been uploaded here.

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
The cell checker evaluates all seven original notebooks twice. Actual Livebook
parser/runtime checks are separate; commands are in README.md. Disposable
copies protect authoritative notebook files from autosave. Notebook text and
lesson code remain verbatim; only setup cells may be changed.

Graphviz is optional. Without `dot`, default snapshots return DOT text and JSON
snapshots work normally. Automatic rendering also returns native DOT if Graphviz
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
  require an explicit release request. Nothing has been published.

## Results in this workspace

Elixir 1.20.4, OTP 29.1.1, Rust 1.98.1, Debian 13/glibc 2.41; QEMU user emulation
for ARM64 and Wine 10 with the official Windows OTP ZIP for Windows x86-64.

- Linux: **78 passed**, including relocation to a path with spaces, both public
  APIs, parsed commands, thread configuration, rollback, int64 limits, snapshots,
  checksum/target/payload rejection, restoration and explicit/automatic renderer
  failure handling. Cargo was absent from `PATH` for installation and tests.
- Windows/Wine: **75 passed**, including real Windows DLL loading, fresh
  dependency compilation and relocation. Three POSIX shell/process renderer
  probes in `graphviz_test.exs` are explicitly skipped on Windows; the timeout-option validation runs on both platforms.
- ARM64/QEMU: **78 checks validated** on the actual ARM64 OTP/BEAM and NIF.
  The complete suite passed 77 checks; the copied-priv regression initially
  inherited `MIX_ENV=test` while expecting a `dev` fixture directory. After
  isolating the child environment, that test passed its targeted rerun. The
  seven installation tests also passed on Linux and Windows after this fix.
  Coverage includes fresh-VM relocation, concurrent installs, restoration,
  native queries and renderer failure handling. The separate native smoke
  check also passed. These are emulated results, not native hardware validation.
- Livebook 0.19.9: **all seven original notebooks passed** through its parser,
  Standalone runtime and Kino (139 executable cells). The cell checker also
  evaluated all seven twice without Graphviz on Linux and Windows/Wine. The same
  lesson cells also passed twice on ARM64 BEAM/NIF under QEMU, using preloaded
  Kino/Jason/Table BEAM files; this ARM check does not exercise dependency
  installation or Livebook's Standalone runtime. No notebook files were edited.
- The actual Hex archive built successfully (about **8.9 MiB**, three bundles).
  It was unpacked and installed with an **empty PATH**: no Cargo, Rust, C
  compiler, make or Graphviz. Both APIs, queries, extraction, rollback, snapshots
  and default DOT rendering passed from the packaged application.
- Linux `ldd` shows only bundled private `libgcc_s`, glibc and libm. Windows PE
  imports contain only Windows system DLLs; no MinGW/C++ runtime install is
  required. Bundles include resolved crate and system runtime notices.

The cached ARM runtime uses matching host `erlexec`, `erl_child_setup` and
`inet_gethost` executables because this container lacks binfmt registration.
The host launcher parses VM flags and invokes an ARM64 BEAM through a QEMU
wrapper; spawned Elixir VMs use the same wrapper. The BEAM, native OTP libraries
and NIF are ARM64; full-system or native ARM testing remains pending. Portable
OTP/Elixir library BEAM files match the tested OTP version.
All emulation roots, generated test copies and detailed logs remain outside
the repo. The workspace Containerfile retains cross compilers, Rust target
libraries, Wine and QEMU for repeat builds.
