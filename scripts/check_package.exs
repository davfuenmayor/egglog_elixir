# Conservative Hex publication limits: 8,000,000 bytes compressed / 64,000,000 bytes uncompressed.
{flags, [path], []} = OptionParser.parse(System.argv(), strict: [release: :boolean])
compressed = File.stat!(path).size
{:ok, outer} = :erl_tar.extract(String.to_charlist(path), [:memory])
{_, contents} = List.keyfind(outer, ~c"contents.tar.gz", 0)
uncompressed = contents |> :zlib.gunzip() |> byte_size()

if compressed >= 8_000_000 or uncompressed >= 64_000_000,
  do: raise("Package exceeds publication size budget")

{:ok, files} = :erl_tar.extract({:binary, contents}, [:compressed, :memory])

for {name, _} <- files do
  if Regex.match?(
       ~r/\.(so(?:\.\d+)*|dll|dylib|a|lib|exe|pdb|zip|tar(?:\.gz|\.xz|\.zst)?|tgz)$/i,
       to_string(name)
     ),
     do: raise("Native binary/archive leaked into source package: #{name}")
end

{_, manifest} =
  List.keyfind(files, ~c"native/manifest.json", 0) || raise "Missing native manifest"

# Run from the checkout used to build the package, after reviewing the native matrix.
if flags[:release] do
  Mix.start()
  Code.require_file("mix.exs")
  release = "v#{Mix.Project.config()[:version]}"
  native = JSON.decode!(manifest)

  unless List.keyfind(files, ~c"mix.exs", 0) == {~c"mix.exs", File.read!("mix.exs")} and
           manifest == File.read!("native/manifest.json") and native["release"] == release and
           native["source_sha256"] == Mix.Tasks.Compile.EgglogNative.source_fingerprint(),
         do: raise("Package needs the reviewed native manifest for #{release}")
end

IO.puts(
  "PASS package: #{compressed} bytes compressed, #{uncompressed} bytes uncompressed; no native binaries"
)
