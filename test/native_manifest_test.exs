defmodule Egglog.NativeManifestTest do
  use ExUnit.Case, async: false
  @targets ~w(linux-x86_64 linux-aarch64 windows-x86_64 macos-x86_64 macos-aarch64)
  @root Path.expand("..", __DIR__)
  @version Mix.Project.config()[:version]

  @tag :tmp_dir
  test "prepares all five reviewed artifacts without changing the source manifest", %{
    tmp_dir: dir
  } do
    artifacts = fixtures(dir)
    original = File.read!("native/manifest.json")
    assert {output, 0} = prepare(dir)
    result = JSON.decode!(output)
    assert result["artifacts"] == artifacts
    assert result["source_sha256"] == Mix.Tasks.Compile.EgglogNative.source_fingerprint()
    assert result["release"] == "v#{@version}"
    assert File.read!("native/manifest.json") == original
  end

  @tag :tmp_dir
  test "rejects incomplete matrices and native provenance mismatches", %{tmp_dir: dir} do
    fixtures(dir)
    file = Path.join(dir, "egglog-#{@version}-macos-aarch64.tar.gz")
    File.rm!(file)
    assert {output, status} = prepare(dir)
    assert status != 0
    assert output =~ "macos-aarch64"
    fixtures(dir)

    File.write!(file, "changed after build", [:append])
    assert {output, status} = prepare(dir)
    assert status != 0
    assert output =~ "archive checksum mismatch"
    fixtures(dir)

    metadata =
      (file <> ".json") |> File.read!() |> JSON.decode!() |> Map.put("source_sha256", "wrong")

    File.write!(file <> ".json", JSON.encode!(metadata))
    assert {output, status} = prepare(dir)
    assert status != 0
    assert output =~ "native source mismatch"
  end

  defp fixtures(dir) do
    source = Mix.Tasks.Compile.EgglogNative.source_fingerprint()

    Map.new(@targets, fn target ->
      file = "egglog-#{@version}-#{target}.tar.gz"
      path = Path.join(dir, file)
      File.write!(path, "fixture #{target}")
      hash = :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)
      File.write!(path <> ".sha256", hash <> "\n")

      metadata = %{"target" => target, "sha256" => hash, "source_sha256" => source}
      File.write!(path <> ".json", JSON.encode!(metadata))
      {target, %{"file" => file, "sha256" => hash, "build" => metadata}}
    end)
  end

  defp prepare(dir) do
    System.cmd(
      System.find_executable("elixir"),
      ["--erl", "+S 1:1", "scripts/prepare_native_manifest.exs", dir, "v#{@version}"],
      cd: @root,
      stderr_to_stdout: true
    )
  end
end
