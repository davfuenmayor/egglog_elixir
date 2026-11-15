defmodule Egglog.NativeBundleTest do
  use ExUnit.Case, async: false

  @root Path.expand("..", __DIR__)
  @version Mix.Project.config()[:version]
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
    app = Path.join([dir, "moved app", "egglog_elixir-#{@version}"])
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

    # Exercise a copied priv directory even when Mix creates a directory symlink.
    if match?({:ok, _}, File.read_link(app_priv)) do
      File.rm_rf!(app_priv)
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

  @tag :tmp_dir
  test "downloads a trusted release, reuses cache offline and repairs corruption", %{tmp_dir: dir} do
    {archive, manifest} = release_fixture(dir)
    data = File.read!(archive)
    {url, listener} = serve(data)
    on_exit(fn -> :gen_tcp.close(listener) end)

    env = [
      {"EGGLOG_ELIXIR_BUNDLE", nil},
      {"EGGLOG_CACHE_DIR", Path.join(dir, "cache")},
      {"EGGLOG_RELEASE_BASE_URL", url}
    ]

    assert {_, 0} = install(dir, env)
    assert_received :download
    assert {_, 0} = install(dir, env)
    refute_received :download
    item = manifest["artifacts"][target()]
    cached = Path.join([dir, "cache", item["sha256"], item["file"]])
    File.write!(cached, "corrupt")
    assert {_, 0} = install(dir, env)
    assert_received :download
    assert File.read!(cached) == data
    :gen_tcp.close(listener)
    assert {_, 0} = install(dir, env)
  end

  @tag :tmp_dir
  test "downloads during Mix compilation with pruned code paths", %{tmp_dir: dir} do
    {archive, _manifest} = release_fixture(dir)
    {url, listener} = serve(File.read!(archive))
    on_exit(fn -> :gen_tcp.close(listener) end)

    mixfile = Path.join(dir, "mix.exs")
    File.write!(mixfile, String.replace(File.read!(mixfile), "deps: deps(),", "deps: [],"))

    # Hex may start HTTPS applications before Mix prunes undeclared code paths.
    code = """
    Mix.start()
    Code.require_file("mix.exs")
    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)
    Mix.Task.run("compile")
    """

    env = [
      {"EGGLOG_ELIXIR_BUNDLE", nil},
      {"EGGLOG_CACHE_DIR", Path.join(dir, "cache")},
      {"EGGLOG_RELEASE_BASE_URL", url}
    ]

    {output, status} = install(dir, env, code)
    assert status == 0, output
    assert_received :download
  end

  @tag :tmp_dir
  test "concurrent cold downloads install one verified cache entry", %{tmp_dir: dir} do
    {archive, manifest} = release_fixture(dir)
    {url, listener} = serve(File.read!(archive))
    on_exit(fn -> :gen_tcp.close(listener) end)

    env = [
      {"EGGLOG_ELIXIR_BUNDLE", nil},
      {"EGGLOG_CACHE_DIR", Path.join(dir, "cache")},
      {"EGGLOG_RELEASE_BASE_URL", url}
    ]

    1..3
    |> Task.async_stream(fn _ -> install(dir, env) end, timeout: 30_000)
    |> Enum.each(fn result -> assert {:ok, {_, 0}} = result end)

    item = manifest["artifacts"][target()]

    assert File.read!(Path.join([dir, "cache", item["sha256"], item["file"]])) ==
             File.read!(archive)

    assert Path.wildcard(Path.join(dir, "cache/**/*.tmp")) == []
  end

  @tag :tmp_dir
  test "rejects a corrupt download and changed native sources", %{tmp_dir: dir} do
    release_fixture(dir)
    {url, listener} = serve("not the reviewed archive")
    on_exit(fn -> :gen_tcp.close(listener) end)

    env = [
      {"EGGLOG_ELIXIR_BUNDLE", nil},
      {"EGGLOG_CACHE_DIR", Path.join(dir, "cache")},
      {"EGGLOG_RELEASE_BASE_URL", url}
    ]

    assert {output, status} = install(dir, env)
    assert status != 0
    assert output =~ "checksum mismatch"
    refute File.exists?(Path.join(dir, "priv/native"))
    assert_received :download
    File.write!(Path.join(dir, "native/egglog_nif/Cargo.toml"), "changed")
    assert {output, status} = install(dir, env)
    assert status != 0
    assert output =~ "Native sources do not match"
    refute_received :download
  end

  defp release_fixture(dir) do
    archive = project(dir)
    bundle(archive, target())

    File.mkdir_p!(Path.join(dir, "native/egglog_nif"))

    for name <- ["src", "Cargo.toml", "Cargo.lock"] do
      File.cp_r!(
        Path.join([@root, "native/egglog_nif", name]),
        Path.join([dir, "native/egglog_nif", name])
      )
    end

    manifest = "native/manifest.json" |> File.read!() |> JSON.decode!()

    item = %{
      "file" => Path.basename(archive),
      "sha256" => String.trim(File.read!(archive <> ".sha256"))
    }

    manifest =
      manifest
      |> Map.put("artifacts", %{target() => item})
      |> Map.put("source_sha256", @compiler.source_fingerprint())

    File.write!(Path.join(dir, "native/manifest.json"), JSON.encode!(manifest))
    {archive, manifest}
  end

  defp serve(data) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, port} = :inet.port(listener)
    parent = self()
    spawn(fn -> serve_next(listener, data, parent) end)
    {"http://127.0.0.1:#{port}", listener}
  end

  defp serve_next(listener, data, parent) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        {:ok, _request} = :gen_tcp.recv(socket, 0, 5000)
        send(parent, :download)

        :gen_tcp.send(socket, [
          "HTTP/1.1 200 OK\r\nContent-Length: #{byte_size(data)}\r\nConnection: close\r\n\r\n",
          data
        ])

        :gen_tcp.close(socket)
        serve_next(listener, data, parent)

      {:error, :closed} ->
        :ok
    end
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
    archive = Path.join(dir, "native/precompiled/egglog-#{@version}-#{target()}.tar.gz")
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

  defp install(
         dir,
         extra_env \\ [],
         code \\ "Mix.start(); Code.require_file(\"mix.exs\"); Mix.Tasks.Compile.EgglogNative.run([])"
       ) do
    System.cmd(System.find_executable("elixir"), ["--erl", "+S 1:1", "-e", code],
      cd: dir,
      stderr_to_stdout: true,
      env:
        Map.to_list(
          Map.merge(
            Map.new([
              {"MIX_ENV", "dev"},
              {"EGGLOG_BUILD", nil},
              {"EGGLOG_ELIXIR_BUNDLE",
               Path.join(dir, "native/precompiled/egglog-#{@version}-#{target()}.tar.gz")},
              {"RUSTLER_PRECOMPILED_FORCE_BUILD_ALL", nil}
            ]),
            Map.new(extra_env)
          )
        )
    )
  end
end
