# Maintaining EgglogElixir

## Current state: do not publish Hex yet

The source package is small and contains no native binaries. The installer,
external cache, native CI and draft-release tooling are implemented locally.
The manifest currently contains imported checksums for three legacy artifacts;
it has no reviewed Mac entries. **The five-platform workflow has not run here,
and this change has not published any release assets.** A fresh machine cannot
rely on the release-download path until those assets are published.

For local work meanwhile, use `EGGLOG_BUILD=1 mix compile`, or set
`EGGLOG_ELIXIR_BUNDLE` to an external archive with its `.sha256` sidecar.
Local build outputs default to `~/.cache/egglog-elixir/artifacts/`.

## Prerequisites

Use authenticated GitHub CLI with access to Actions artifacts and release drafts.
The package's default download location must serve assets anonymously before public
Hex publication; an authenticated local override does not prove this. Keep release
credentials out of build jobs. Enable immutable releases under repository
**Settings → Releases → Enable release immutability** before publication;
[GitHub's release guidance](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases)
explains the draft-first process.

## Finish this migration

1. Review and commit the migration, including archive deletions, manifest, source
   and CI definitions. Push a branch/PR to run **Native builds**; keep the migration
   off the default branch until native downloads are published and verified. No history
   rewrite is needed. Use shallow clones to avoid downloading old binary history.
2. Review all ten jobs: five native platforms, each with minimum/current BEAM.
   Jobs build with Rust 1.91, run tests, inspect dependencies, exercise Graphviz
   and automatic Mermaid fallback, and test an unpacked Hex package with empty PATH.
   CI has no publishing permission. A passing configuration file is not a test run.
3. Obtain one tested artifact per platform from the same reviewed run, normally
   the OTP 27 jobs. Keep the archive, `.sha256` and `.json` together:

   ```sh
   RUN_ID=YOUR_SUCCESSFUL_RUN_ID
   ARTIFACT_DIR=/tmp/egglog-native-release
   mkdir -p "$ARTIFACT_DIR"
   for target in linux-x86_64 linux-aarch64 windows-x86_64 macos-x86_64 macos-aarch64; do
     gh run download "$RUN_ID" --name "native-$target-otp27" --dir "$ARTIFACT_DIR"
   done
   elixir scripts/prepare_native_manifest.exs "$ARTIFACT_DIR" v0.2.0 > /tmp/candidate.json
   ```

4. Review the candidate against CI logs: targets, source fingerprint, hashes,
   toolchain, NIF runtime version, OS/deployment baselines, flags and licenses.
   Inspect Linux library dependencies, Mac `otool -L` output, and Windows imports.
   Confirm minimum-OS claims separately; testing macOS 15 does not validate macOS 12.
5. Copy the approved candidate to `native/manifest.json`, commit it, and tag the
   reviewed branch commit as `v0.2.0` and push that tag to origin (the publisher
   requires an existing remote tag). Before tagging, update migration notes and platform
   claims to the evidence actually reviewed; public downloads remain gated by
   step 7. If the version/tag already exists, use a new version instead.
   The native fingerprint must still match the CI
   artifacts. If native inputs changed, rebuild and review again.
6. Only when ready to prepare a release, with authenticated `gh` and explicit
   release authorization, run:

   ```sh
   EGGLOG_ARTIFACT_DIR="$ARTIFACT_DIR" MIX_ENV=prod mix run scripts/publish_native.exs
   ```

   The script requires a clean tagged commit and all five manifest-matching
   artifacts, verifies their provenance/sidecars, and creates a **draft**. It
   refuses an existing release. Review draft assets, enable GitHub release
   immutability, then publish the release. Never overwrite assets or move tags.
7. Test anonymous cold-cache installs from the published release on each platform,
   using a clean checkout of the reviewed tag and a fresh temporary `EGGLOG_CACHE_DIR`. Unset offline
   overrides and source-build flags. Verify downloaded hashes, native execution,
   a second offline cache hit and actual Graphviz rendering. Test the unpacked
   source package without an override as well; candidate CI used an override and
   therefore did not prove public release delivery. Do not print authentication tokens.
   On a clean checkout, a concrete cold/warm-cache check is:

   ```sh
   export EGGLOG_CACHE_DIR="$(mktemp -d)"
   unset EGGLOG_ELIXIR_BUNDLE EGGLOG_BUILD RUSTLER_PRECOMPILED_FORCE_BUILD_ALL EGGLOG_RELEASE_BASE_URL
   mix deps.get
   mix compile
   mix run scripts/check_native.exs
   mix run scripts/check_rendering.exs
   EGGLOG_RELEASE_BASE_URL=https://offline.invalid mix compile
   ```

8. Only after those checks, merge the migration into the default branch and
   publish to Hex from a clean checkout of the reviewed release tag. Pin the course to the tested version
   and remove its Mac source-build workaround only after real Mac installs succeed.

## Every subsequent release

1. Update both versions: `mix.exs` and `native/egglog_nif/Cargo.toml`. Regenerate the
   Cargo lockfile as needed. The builder names artifacts using the Cargo version;
   the manifest/release preparation uses the wrapper version, so they must agree.
2. Run the complete native matrix and repeat artifact review, manifest approval,
   clean commit/tag, draft preparation and cold-cache installation checks above.
   Every advertised target needs a reviewed artifact; do not silently ship a partial
   matrix or reuse an older native payload for changed native sources.
3. Keep the changelog, API coverage, platform status and known limitations accurate.
   Record native hardware, emulated and minimum-version results separately.
   Remove completed items from the sole backlog, `egglog_elixir_improvements.md`.
4. Build/test the package and documentation before publication:

   ```sh
   mix test
   mix docs --warnings-as-errors
   mix hex.build -o /tmp/egglog.tar
   elixir scripts/check_package.exs /tmp/egglog.tar
   EGGLOG_CACHE_DIR="$(mktemp -d)" elixir scripts/check_packaged_install.exs /tmp/egglog.tar
   mix hex.publish
   ```

   Keep `EGGLOG_ELIXIR_BUNDLE` unset for the final install check so it exercises
   published downloads. The size guard enforces conservative 8 MB compressed /
   64 MB uncompressed package budgets and rejects native binaries/archives. Hex
   publishes docs too; inspect their size and output. Never publish from a dirty
   tree or while required native downloads fail. Check Hex's current limits at
   <https://hex.hexdocs.pm/Mix.Tasks.Hex.Publish.html> when preparing a release.

## Development and troubleshooting

- Source-build flags apply per invocation. For later commands against a local
  build, keep `EGGLOG_BUILD=1` exported, use `build_from_source` configuration, or
  export `EGGLOG_ELIXIR_BUNDLE` to the archive path printed by the builder.
  Otherwise normal compilation selects the reviewed release again (or rejects
  changed native source), rather than silently adopting a local build.
- Elixir-only changes can use the reviewed manifest/cache. Native Rust or Cargo
  changes invalidate its fingerprint: build explicitly with `EGGLOG_BUILD=1`.
  `.gitattributes` keeps hashed source line endings consistent across platforms.
- `EGGLOG_BUILD_ROOT` selects the external build cache; `EGGLOG_ARTIFACT_DIR`
  selects build outputs. Build outputs are not committed or included in Hex.
- `EGGLOG_CACHE_DIR` selects the download cache. Only an archive matching the
  manifest digest is accepted; corruption triggers a verified replacement.
  `EGGLOG_RELEASE_BASE_URL` supports managed HTTPS mirrors, not checksum bypasses.
- `EGGLOG_ELIXIR_BUNDLE` is an explicit trusted offline override. Supply its
  sidecar; this path deliberately bypasses release source matching. A forced
  source build takes precedence over that override.
- A missing Mac manifest entry is a delivery gap, not successful Mac support.
  If download fails, check the manifest's release/file and public asset access.
  Do not change digests merely to silence errors. Restart BEAM after replacing a NIF.
- Correct a bad published binary with a new version/release and fresh hashes.
  Never replace an immutable asset, move a release tag, or roll back to a mismatched
  artifact. Use Hex's supported retirement/release process for affected versions.
- Local tests do not run GitHub jobs, enable release immutability, validate native
  Mac/Windows hardware, or publish anything. Those are explicit maintainer steps.
