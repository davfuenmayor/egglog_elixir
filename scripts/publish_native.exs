# Run after committing/tagging the release and packaging its native artifact:
# MIX_ENV=prod mix run scripts/publish_native.exs
version = Mix.Project.config()[:version]
tag = "v#{version}"

run! = fn command, args ->
  case System.cmd(command, args, stderr_to_stdout: true) do
    {output, 0} -> String.trim(output)
    {output, _} -> raise "#{command} failed: #{output}"
  end
end

gh =
  System.find_executable("gh") ||
    raise "Publishing needs GitHub CLI (gh) and authenticated release access."

run!.(gh, ["auth", "status"])

unless run!.("git", ["status", "--porcelain"]) == "",
  do: raise("Commit the reviewed release changes before publishing.")

unless run!.("git", ["rev-parse", "HEAD"]) ==
         run!.("git", ["rev-parse", "refs/tags/#{tag}^{commit}"]),
       do: raise("The release tag #{tag} must point to the current source commit.")

archives =
  Path.wildcard("native/precompiled/egglog-#{version}-*.tar.gz")
  |> Enum.map(fn path ->
    expected = File.read!(path <> ".sha256") |> String.trim()
    actual = :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)
    unless actual == expected, do: raise("Artifact checksum mismatch: #{path}")
    path
  end)

if archives == [], do: raise("Package native artifacts before publishing.")

repo = "davfuenmayor/egglog_elixir"

case System.cmd(gh, ["release", "view", tag, "--repo", repo], stderr_to_stdout: true) do
  {_, 0} -> raise "Release #{tag} already exists; its artifacts will not be replaced."
  _ -> :ok
end

notes = Path.join("dist", "release_notes.md")
File.mkdir_p!("dist")

File.write!(
  notes,
  "Egglog Elixir #{version}\n\nThin bindings for egglog 3.0.0. See CHANGELOG.md and API_COVERAGE.md at this tag.\n"
)

run!.(
  gh,
  [
    "release",
    "create",
    tag,
    "--repo",
    repo,
    "--verify-tag",
    "--title",
    "Egglog Elixir #{version}",
    "--notes-file",
    notes
  ] ++ Enum.flat_map(archives, &[&1, &1 <> ".sha256"])
)

IO.puts("Published #{repo} release #{tag} with verified native artifacts.")
