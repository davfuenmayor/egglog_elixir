defmodule Egglog.NativeBundleTest do
  use ExUnit.Case, async: false

  @root Path.expand("..", __DIR__)
  @compiler Mix.Tasks.Compile.EgglogNative

  test "selects only supported 64-bit native targets" do
    for {os, arch, expected} <- [
          {{:unix, :linux}, "x86_64-pc-linux-gnu", "linux-x86_64"},
          {{:unix, :linux}, "aarch64-unknown-linux-gnu", "linux-aarch64"},
          {{:unix, :darwin}, "x86_64-apple-darwin", "macos-x86_64"},
          {{:unix, :darwin}, "arm64-apple-darwin", "macos-aarch64"},
          {{:win32, :nt}, "AMD64", "windows-x86_64"}
        ] do
      assert @compiler.target(os, arch) == expected
    end

    for {os, arch} <- [
          {{:unix, :linux}, "x86_64-unknown-linux-musl"},
          {{:unix, :linux}, "i686-pc-linux-gnu"},
          {{:win32, :nt}, "ARM64"}
        ] do
      assert_raise Mix.Error, ~r/Unsupported Egglog platform/, fn ->
        @compiler.target(os, arch)
      end
    end
  end

  @tag :tmp_dir
  test "installed app works after relocation in a fresh VM", %{tmp_dir: dir} do
    app = Path.join([dir, "moved app", "egglog_elixir-0.2.0"])
    jason = Path.join([dir, "moved app", "jason"])
    File.mkdir_p!(Path.join(app, "priv"))
    File.mkdir_p!(jason)
    File.cp_r!(Application.app_dir(:jason, "ebin"), Path.join(jason, "ebin"))
    File.cp_r!(Application.app_dir(:egglog_elixir, "ebin"), Path.join(app, "ebin"))
    File.cp_r!(Application.app_dir(:egglog_elixir, "priv/native"), Path.join(app, "priv/native"))

    script = Path.join(dir, "native_smoke.exs")
    File.cp!(Path.join(@root, "scripts/check_native.exs"), script)

    assert {output, 0} =
             System.cmd(
               System.find_executable("elixir"),
               [
                 "--erl",
                 "+S 1:1",
                 "-pa",
                 Path.join(app, "ebin"),
                 "-pa",
                 Path.join(jason, "ebin"),
                 script
               ],
               cd: dir,
               stderr_to_stdout: true
             )

    assert output =~ "PASS native queries"
  end

  @tag :tmp_dir
  test "installs without Cargo and restores a missing payload", %{tmp_dir: dir} do
    archive = project(dir)
    bundle(archive, target())
    assert {_, 0} = install(dir)
    assert File.read!(Path.join(dir, "priv/native/egglog_nif.#{extension()}")) == "fixture NIF"
    assert {_, 0} = install(dir)
    File.rm!(Path.join(dir, "priv/native/egglog_nif.#{extension()}"))
    assert {_, 0} = install(dir)
    assert File.regular?(Path.join(dir, "priv/native/egglog_nif.#{extension()}"))

    if :os.type() == {:unix, :linux} do
      File.rm!(Path.join(dir, "priv/native/egglog_libgcc_s.so.1"))
      assert {_, 0} = install(dir)
      assert File.regular?(Path.join(dir, "priv/native/egglog_libgcc_s.so.1"))
    end
  end

  @tag :tmp_dir
  test "simultaneous fresh installs share one valid native payload", %{tmp_dir: dir} do
    archive = project(dir)
    bundle(archive, target())

    1..3
    |> Task.async_stream(fn _ -> install(dir) end, timeout: 30_000)
    |> Enum.each(fn result -> assert {:ok, {_, 0}} = result end)

    assert File.regular?(Path.join(dir, "priv/native/egglog_nif.#{extension()}"))
  end

  @tag :tmp_dir
  test "restores missing files in a copied application priv directory", %{tmp_dir: dir} do
    archive = project(dir)
    bundle(archive, target())
    assert {_, 0} = install(dir)
    app_priv = Path.join(dir, "_build/dev/lib/egglog_elixir/priv")

    # Windows copies priv; emulate that layout on hosts that use symlinks.
    if match?({:ok, _}, File.read_link(app_priv)) do
      File.rm!(app_priv)
      File.cp_r!(Path.join(dir, "priv"), app_priv)
    end

    for file <-
          ["egglog_nif.#{extension()}"] ++
            if(:os.type() == {:unix, :linux}, do: ["egglog_libgcc_s.so.1"], else: []) do
      installed = Path.join([app_priv, "native", file])
      File.rm!(installed)
      assert {_, 0} = install(dir)
      assert File.regular?(installed)
    end
  end

  @tag :tmp_dir
  test "rejects corrupted archives before installation", %{tmp_dir: dir} do
    archive = project(dir)
    bundle(archive, target())
    File.write!(archive, "tampered", [:append])
    assert {output, status} = install(dir)
    assert status != 0
    assert output =~ "checksum mismatch"
    refute File.exists?(Path.join(dir, "priv/native"))
  end

  @tag :tmp_dir
  test "rejects wrong-target and incomplete archives", %{tmp_dir: dir} do
    archive = project(dir)
    bundle(archive, "wrong-target")
    assert {output, status} = install(dir)
    assert status != 0
    assert output =~ "does not match"
    refute File.exists?(Path.join(dir, "priv/native"))

    bundle(archive, target(), false)
    assert {output, status} = install(dir)
    assert status != 0
    assert output =~ "missing its NIF"
    refute File.exists?(Path.join(dir, "priv/native"))
  end

  defp target do
    arch =
      if :os.type() == {:win32, :nt},
        do: System.fetch_env!("PROCESSOR_ARCHITECTURE"),
        else: to_string(:erlang.system_info(:system_architecture))

    @compiler.target(:os.type(), arch)
  end

  defp extension, do: if(:os.type() == {:win32, :nt}, do: "dll", else: "so")

  defp project(dir) do
    File.cp!(Path.join(@root, "mix.exs"), Path.join(dir, "mix.exs"))
    archive = Path.join(dir, "native/precompiled/egglog-0.2.0-#{target()}.tar.gz")
    File.mkdir_p!(Path.dirname(archive))
    archive
  end

  defp bundle(archive, platform, complete? \\ true) do
    files = [{~c"native/target", platform <> "\n"}]

    files =
      if complete?,
        do:
          files ++
            [
              {String.to_charlist("native/egglog_nif.#{extension()}"), "fixture NIF"}
            ],
        else: files

    files =
      if complete? and :os.type() == {:unix, :linux},
        do: files ++ [{~c"native/egglog_libgcc_s.so.1", "fixture runtime"}],
        else: files

    :ok = :erl_tar.create(String.to_charlist(archive), files, [:compressed])
    hash = :crypto.hash(:sha256, File.read!(archive)) |> Base.encode16(case: :lower)
    File.write!(archive <> ".sha256", hash <> "\n")
  end

  defp install(dir) do
    code = "Mix.start(); Code.require_file(\"mix.exs\"); Mix.Tasks.Compile.EgglogNative.run([])"

    System.cmd(System.find_executable("elixir"), ["--erl", "+S 1:1", "-e", code],
      cd: dir,
      stderr_to_stdout: true,
      env: [
        {"MIX_ENV", "dev"},
        {"EGGLOG_BUILD", nil},
        {"EGGLOG_ELIXIR_BUNDLE", nil},
        {"RUSTLER_PRECOMPILED_FORCE_BUILD_ALL", nil}
      ]
    )
  end
end
