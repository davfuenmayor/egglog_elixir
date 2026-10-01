# Run with: MIX_ENV=prod mix run scripts/package_native.exs
unless Application.get_env(:egglog_elixir, :build_from_source, true),
  do: raise("package native artifacts from a source build")

{:ok, host_target} = RustlerPrecompiled.target()
["nif", _host_nif_version, triple] = String.split(host_target, "-", parts: 3)
# Rustler's default Cargo feature compiles against NIF API 2.15.
target = "nif-2.15-#{triple}"

unless triple == "x86_64-unknown-linux-gnu",
  do: raise("this artifact target is not yet verified: #{target}")

version = Mix.Project.config()[:version]
filename = "libegglog_nif-v#{version}-#{target}.so"
archive = Path.join("dist", filename <> ".tar.gz")
File.mkdir_p!("dist")
binary = File.read!(Application.app_dir(:egglog_elixir, "priv/native/egglog_nif.so"))

:ok =
  :erl_tar.create(
    String.to_charlist(archive),
    [
      {String.to_charlist(filename), binary},
      {~c"LICENSE", File.read!("LICENSE")},
      {~c"LICENSE-EGGLOG-MIT", File.read!("native/egglog_nif/LICENSE-EGGLOG-MIT")}
    ],
    [:compressed]
  )

checksum = :crypto.hash(:sha256, File.read!(archive)) |> Base.encode16(case: :lower)

File.write!(
  "checksum-Elixir.Egglog.Native.exs",
  [Code.format_string!(inspect(%{Path.basename(archive) => "sha256:#{checksum}"})), "\n"]
)

IO.puts("Prepared #{archive}; checksum recorded. No upload performed.")
