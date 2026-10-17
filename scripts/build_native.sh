#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
host=$(rustc -vV | awk '$1 == "host:" { print $2 }')
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) default=linux-x86_64 ;;
  Linux-aarch64) default=linux-aarch64 ;;
  Darwin-x86_64) default=macos-x86_64 ;;
  Darwin-arm64) default=macos-aarch64 ;;
  MINGW*-x86_64|MSYS*-x86_64) default=windows-x86_64 ;;
  *) echo 'Unsupported native build host' >&2; exit 1 ;;
esac
[[ "$host" != *musl* ]] || { echo 'musl is not supported' >&2; exit 1; }
target=${EGGLOG_TARGET:-$default}
cache=${EGGLOG_BUILD_ROOT:-${XDG_CACHE_HOME:-$HOME/.cache}/egglog-elixir}
mkdir -p "$cache" native/precompiled
cache=$(cd "$cache" && pwd -P)
export CARGO_BUILD_JOBS=${BUILD_JOBS:-4}
args=()
case "$target" in
  linux-x86_64)
    [[ "$default" == linux-x86_64 ]] || { echo 'Build this target on Linux x86-64' >&2; exit 1; }
    triple=x86_64-unknown-linux-gnu; compiler=${CC:-cc}; stripper=strip
    export CARGO_TARGET_DIR="$cache/target"
    output="$CARGO_TARGET_DIR/release"
    library=libegglog_nif.so; extension=so ;;
  linux-aarch64)
    [[ "$default" == linux-* ]] || { echo 'Build Linux targets on Linux' >&2; exit 1; }
    triple=aarch64-unknown-linux-gnu
    if [[ "$default" == linux-aarch64 ]]; then compiler=${CC:-cc}; stripper=strip
    else compiler=aarch64-linux-gnu-gcc; stripper=aarch64-linux-gnu-strip; fi
    export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER="$compiler"
    export CARGO_TARGET_DIR="$cache/target-aarch64"
    args=(--target "$triple")
    output="$CARGO_TARGET_DIR/$triple/release"; library=libegglog_nif.so; extension=so ;;
  windows-x86_64)
    if [[ "$host" == x86_64-pc-windows-msvc ]]; then triple=$host
    else
      triple=x86_64-pc-windows-gnu
      export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER=x86_64-w64-mingw32-gcc
    fi
    export RUSTFLAGS="${RUSTFLAGS:-} -C target-feature=+crt-static"
    export CARGO_TARGET_DIR="$cache/target-windows"
    args=(--target "$triple")
    output="$CARGO_TARGET_DIR/$triple/release"; library=egglog_nif.dll; extension=dll ;;
  macos-x86_64|macos-aarch64)
    [[ "$target" == "$default" ]] || { echo 'Build each macOS target on the matching Mac' >&2; exit 1; }
    if [[ "$target" == macos-x86_64 ]]; then triple=x86_64-apple-darwin; else triple=aarch64-apple-darwin; fi
    [[ "$host" == "$triple" ]] || { echo 'Rust toolchain must match the running architecture' >&2; exit 1; }
    export MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-12.0}
    export CARGO_TARGET_DIR="$cache/target-$target"
    output="$CARGO_TARGET_DIR/release"; library=libegglog_nif.dylib; extension=so ;;
  *) echo "Unsupported target: $target" >&2; exit 1 ;;
esac
cargo build --locked --release --manifest-path native/egglog_nif/Cargo.toml "${args[@]}"
cargo metadata --locked --format-version 1 --manifest-path native/egglog_nif/Cargo.toml > "$cache/metadata-$target.json"
version=$(elixir --erl '+S 1:1' -e 'm = File.read!(hd(System.argv())) |> JSON.decode!(); IO.puts(Enum.find(m["packages"], &(&1["name"] == "egglog_nif"))["version"])' "$cache/metadata-$target.json")
stage="$cache/stage/$target"
elixir --erl '+S 1:1' -e 'File.rm_rf!(hd(System.argv()))' "$stage"
mkdir -p "$stage/native/licenses"
cp "$output/$library" "$stage/native/egglog_nif.$extension"
printf '%s\n' "$target" > "$stage/native/target"
cp LICENSE "$stage/native/licenses/LICENSE-EGGLOG-ELIXIR-MIT"
cp native/egglog_nif/LICENSE-EGGLOG-MIT "$stage/native/licenses/"
cp native/egglog_nif/Cargo.lock "$stage/native/"
elixir --erl '+S 1:1' scripts/native_notices.exs "$cache/metadata-$target.json" "$stage/native/licenses"
rust_notices="$(rustc --print sysroot)/share/doc/rust"
if [ ! -f "$rust_notices/COPYRIGHT-library.html" ]; then
  echo 'Rust standard-library notices missing; install rust-docs for this toolchain.' >&2
  exit 1
fi
mkdir -p "$stage/native/licenses/rust"
cp "$rust_notices/COPYRIGHT-library.html" "$stage/native/licenses/rust/"
cp -R "$rust_notices/licenses" "$stage/native/licenses/rust/"
rustc -vV > "$stage/native/licenses/rust/TOOLCHAIN.txt"
case "$target" in
  linux-*)
    binary="$stage/native/egglog_nif.so"
    "$stripper" "$binary"
    patchelf --set-rpath '$ORIGIN' "$binary"
    cp -L "$("$compiler" -print-file-name=libgcc_s.so.1)" "$stage/native/egglog_libgcc_s.so.1"
    patchelf --set-soname egglog_libgcc_s.so.1 "$stage/native/egglog_libgcc_s.so.1"
    patchelf --replace-needed libgcc_s.so.1 egglog_libgcc_s.so.1 "$binary"
    runtime_package=libgcc-s1
    if [[ "$target" == linux-aarch64 && "$default" != linux-aarch64 ]]; then runtime_package=libgcc-s1-arm64-cross; fi
    if [ -f "/usr/share/doc/$runtime_package/copyright" ]; then
      cp -L "/usr/share/doc/$runtime_package/copyright" "$stage/native/licenses/GCC-NOTICES.txt"
      cp /usr/share/common-licenses/GPL-3 "$stage/native/licenses/GPL-3.txt"
      dpkg-query -W -f='${binary:Package} ${Version} | source: ${source:Package} ${source:Version}\n' "$runtime_package" > "$stage/native/licenses/SYSTEM-LIBRARIES.txt"
    fi ;;
  macos-*)
    strip -x "$stage/native/egglog_nif.so"
    codesign --force --sign - "$stage/native/egglog_nif.so" ;;
  windows-*)
    if [[ "$triple" == *-gnu ]]; then
      for package in mingw-w64-common mingw-w64-x86-64-dev gcc-mingw-w64-base gcc-mingw-w64-x86-64-posix-runtime; do
        if [ -f "/usr/share/doc/$package/copyright" ]; then
          cp -L "/usr/share/doc/$package/copyright" "$stage/native/licenses/$package-NOTICES.txt"
        fi
      done
      if command -v dpkg-query >/dev/null; then
        cp /usr/share/common-licenses/GPL-3 "$stage/native/licenses/GPL-3.txt"
        dpkg-query -W -f='${binary:Package} ${Version} | source: ${source:Package} ${source:Version}\n' \
          mingw-w64-common gcc-mingw-w64-x86-64-posix-runtime > "$stage/native/licenses/SYSTEM-LIBRARIES.txt"
      fi
      # Native MSYS2 installations keep their runtime notices here.
      for directory in /mingw64/share/licenses/{gcc-libs,mingw-w64-crt,mingw-w64-headers,winpthreads}; do
        [ ! -d "$directory" ] || cp -R "$directory" "$stage/native/licenses/"
      done
      x86_64-w64-mingw32-strip "$stage/native/egglog_nif.dll"
      # The CRT is static; other imports must be Windows system libraries.
      x86_64-w64-mingw32-objdump -p "$stage/native/egglog_nif.dll" | awk '/DLL Name:/ { print $3 }' > "$stage/native/imports.txt"
      if awk 'tolower($0) ~ /libgcc|libstdc\+\+|libwinpthread/ { found=1 } END { exit !found }' "$stage/native/imports.txt"; then
        echo 'Non-system runtime DLL dependency: check the static CRT build' >&2
        exit 1
      fi
    fi ;;
esac
archive="native/precompiled/egglog-$version-$target.tar.gz"
tar -czf "$archive" -C "$stage" native
elixir --erl '+S 1:1' -e '[file] = System.argv(); hash = :crypto.hash(:sha256, File.read!(file)) |> Base.encode16(case: :lower); File.write!(file <> ".sha256", hash <> "\n")' "$archive"
printf 'Built %s (%s)\n' "$target" "$triple"
