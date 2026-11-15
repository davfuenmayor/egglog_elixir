defmodule EgglogElixir.MixProject do
  use Mix.Project

  def project do
    [
      app: :egglog_elixir,
      version: "0.2.0",
      elixir: "~> 1.19",
      name: "EgglogElixir",
      description: "Thin Elixir wrapper around the native Rust egglog engine.",
      start_permanent: Mix.env() == :prod,
      compilers: [:egglog_native] ++ Mix.compilers(),
      deps: deps(),
      docs: docs(),
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :inets, :ssl]
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "Egglog",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "API_COVERAGE.md",
        "KNOWN_ISSUES.md",
        "egglog_elixir_improvements.md",
        "MULTIPLATFORM.md",
        "MAINTAINING.md",
        "livebooks/README.md",
        "livebooks/egglog-tutorial/LICENSE-UPSTREAM.md",
        "livebooks/index.livemd",
        "livebooks/getting_started.livemd",
        "livebooks/egglog-tutorial/README.md",
        "livebooks/egglog-tutorial/01-basics.livemd",
        "livebooks/egglog-tutorial/02-datalog.livemd",
        "livebooks/egglog-tutorial/03-analysis.livemd",
        "livebooks/egglog-tutorial/04-scheduling.livemd",
        "livebooks/egglog-tutorial/05-cost-model-and-extraction.livemd",
        "livebooks/egglog-tutorial/06-case-study.livemd"
      ],
      groups_for_extras: [
        Livebooks: ~r/livebooks/
      ]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      build_tools: ["mix"],
      links: %{
        "Upstream egglog" => "https://github.com/egraphs-good/egglog",
        "Tutorial" => "https://egraphs-good.github.io/egglog-tutorial/"
      },
      files: [
        ".formatter.exs",
        "CHANGELOG.md",
        "API_COVERAGE.md",
        "KNOWN_ISSUES.md",
        "egglog_elixir_improvements.md",
        "MULTIPLATFORM.md",
        "MAINTAINING.md",
        "native/manifest.json",
        "LICENSE",
        "README.md",
        "lib",
        "livebooks",
        "mix.exs",
        "native/egglog_nif/Cargo.lock",
        "native/egglog_nif/Cargo.toml",
        "native/egglog_nif/src",
        "native/egglog_nif/LICENSE-EGGLOG-MIT",
        "scripts"
      ]
    ]
  end
end

defmodule Mix.Tasks.Compile.EgglogNative do
  use Mix.Task.Compiler

  def run(_) do
    built =
      if Application.get_env(:egglog_elixir, :build_from_source, false) or
           System.get_env("EGGLOG_BUILD") in ["1", "true"] or
           System.get_env("RUSTLER_PRECOMPILED_FORCE_BUILD_ALL") in ["1", "true"] do
        {output, status} = System.cmd("bash", ["scripts/build_native.sh"], stderr_to_stdout: true)
        Mix.shell().info(output)
        if status != 0, do: Mix.raise("Egglog source build failed")

        case Regex.run(~r/^EGGLOG_NATIVE_ARCHIVE=(.+)$/m, output) do
          [_, path] -> path
          _ -> Mix.raise("Source build did not report its archive")
        end
      end

    if :erlang.system_info(:wordsize) != 8,
      do: Mix.raise("egglog_elixir requires a 64-bit Erlang runtime")

    os = :os.type()

    arch =
      if os == {:win32, :nt},
        do: System.get_env("PROCESSOR_ARCHITECTURE", "unknown"),
        else: to_string(:erlang.system_info(:system_architecture))

    target = target(os, arch)

    {:ok, _} = Application.ensure_all_started(:crypto)

    {archive, expected} =
      case built || System.get_env("EGGLOG_ELIXIR_BUNDLE") do
        nil -> release_bundle(target)
        path -> {path, File.read!(path <> ".sha256") |> String.trim()}
      end

    unless valid_archive?(archive, expected),
      do: Mix.raise("Egglog native archive checksum mismatch")

    extension = if os == {:win32, :nt}, do: "dll", else: "so"
    filename = "egglog_nif.#{extension}"
    files = [filename] ++ if(os == {:unix, :linux}, do: ["egglog_libgcc_s.so.1"], else: [])

    installed? = fn ->
      File.read("priv/native/.bundle") == {:ok, expected} and
        Enum.all?(files, &File.regular?(Path.join("priv/native", &1)))
    end

    unless installed?.() do
      staging = "_build/.egglog-unpack-#{System.pid()}-#{System.unique_integer([:positive])}"
      File.mkdir_p!(staging)

      try do
        case :erl_tar.extract(String.to_charlist(archive), [
               :compressed,
               {:cwd, String.to_charlist(staging)}
             ]) do
          :ok -> :ok
          {:error, reason} -> Mix.raise("Cannot unpack Egglog native bundle: #{inspect(reason)}")
        end

        native = Path.join(staging, "native")

        unless File.read(Path.join(native, "target")) == {:ok, target <> "\n"},
          do: Mix.raise("Egglog bundle does not match #{target}")

        unless Enum.all?(files, &File.regular?(Path.join(native, &1))),
          do: Mix.raise("Egglog bundle is missing its NIF or runtime library")

        File.write!(Path.join(native, ".bundle"), expected)

        unless installed?.() do
          File.mkdir_p!("priv")

          case File.rename(native, "priv/native") do
            :ok ->
              :ok

            {:error, reason} ->
              # Another VM may have installed the same bundle while we unpacked.
              unless installed?.() do
                File.rm_rf!("priv/native")

                case File.rename(native, "priv/native") do
                  :ok ->
                    :ok

                  {:error, retry_reason} ->
                    unless installed?.(),
                      do:
                        Mix.raise(
                          "Cannot install Egglog bundle: #{inspect({reason, retry_reason})}"
                        )
                end
              end
          end
        end
      after
        File.rm_rf!(staging)
      end
    end

    Mix.Project.build_structure()
    app_priv = Path.join(Mix.Project.app_path(), "priv")

    unless File.read(Path.join(app_priv, "native/.bundle")) == {:ok, expected} and
             Enum.all?(files, &File.regular?(Path.join([app_priv, "native", &1]))),
           do: File.cp_r!("priv", app_priv)

    {:ok, []}
  end

  def source_fingerprint do
    paths =
      Enum.sort(
        Path.wildcard("native/egglog_nif/src/**/*.rs") ++
          ["native/egglog_nif/Cargo.toml", "native/egglog_nif/Cargo.lock"]
      )

    :crypto.hash(:sha256, Enum.map(paths, &[&1, <<0>>, File.read!(&1), <<0>>]))
    |> Base.encode16(case: :lower)
  end

  defp valid_archive?(path, expected) do
    case File.read(path) do
      {:ok, data} -> Base.encode16(:crypto.hash(:sha256, data), case: :lower) == expected
      _ -> false
    end
  end

  defp release_bundle(target) do
    manifest = "native/manifest.json" |> File.read!() |> JSON.decode!()

    unless manifest["schema"] == 1 and manifest["source_sha256"] == source_fingerprint(),
      do: Mix.raise("Native sources do not match the artifact manifest; use EGGLOG_BUILD=1")

    artifact =
      manifest["artifacts"][target] ||
        Mix.raise(
          "No reviewed release artifact for #{target}; use EGGLOG_BUILD=1. See MULTIPLATFORM.md"
        )

    %{"file" => file, "sha256" => hash} = artifact

    unless Path.basename(file) == file and Regex.match?(~r/^[a-f0-9]{64}$/, hash),
      do: Mix.raise("Invalid Egglog artifact manifest")

    cache =
      System.get_env("EGGLOG_CACHE_DIR") ||
        to_string(:filename.basedir(:user_cache, ~c"egglog_elixir"))

    path = Path.join([cache, hash, file])

    unless valid_archive?(path, hash) do
      base =
        System.get_env("EGGLOG_RELEASE_BASE_URL") ||
          "https://github.com/davfuenmayor/egglog_elixir/releases/download"

      url = String.trim_trailing(base, "/") <> "/" <> manifest["release"] <> "/" <> file
      download_archive!(url, path, hash)
    end

    {path, hash}
  end

  defp download_archive!(url, path, hash) do
    uri = URI.parse(url)

    unless uri.scheme == "https" or
             (uri.scheme == "http" and uri.host in ["127.0.0.1", "localhost"]),
           do: Mix.raise("Artifact downloads require HTTPS")

    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)

    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    data =
      case :httpc.request(
             :get,
             {String.to_charlist(url), []},
             [ssl: ssl, timeout: 60_000, connect_timeout: 10_000],
             body_format: :binary
           ) do
        {:ok, {{_, 200, _}, _, data}} ->
          data

        result ->
          Mix.raise(
            "Cannot download reviewed Egglog artifact #{url}: #{inspect(result)}. " <>
              "Publish matching release assets or use EGGLOG_ELIXIR_BUNDLE / EGGLOG_BUILD=1"
          )
      end

    unless Base.encode16(:crypto.hash(:sha256, data), case: :lower) == hash,
      do: Mix.raise("Downloaded Egglog archive checksum mismatch")

    File.mkdir_p!(Path.dirname(path))
    temporary = path <> ".#{System.pid()}.#{System.unique_integer([:positive])}.tmp"

    try do
      File.write!(temporary, data, [:exclusive])

      case File.rename(temporary, path) do
        :ok ->
          :ok

        {:error, reason} ->
          unless valid_archive?(path, hash) do
            File.rm(path)

            case File.rename(temporary, path) do
              :ok ->
                :ok

              {:error, _} ->
                unless valid_archive?(path, hash),
                  do: Mix.raise("Cannot cache archive: #{inspect(reason)}")
            end
          end
      end
    after
      File.rm(temporary)
    end
  end

  def clean do
    File.rm_rf!("priv/native")
    :ok
  end

  def target(os, arch) do
    cpu = arch |> String.split("-") |> hd()

    case {os, cpu, String.contains?(arch, "musl")} do
      {{:unix, :linux}, "x86_64", false} ->
        "linux-x86_64"

      {{:unix, :linux}, "aarch64", false} ->
        "linux-aarch64"

      {{:unix, :darwin}, "x86_64", false} ->
        "macos-x86_64"

      {{:unix, :darwin}, cpu, false} when cpu in ["arm64", "aarch64"] ->
        "macos-aarch64"

      {{:win32, :nt}, cpu, false} when cpu in ["AMD64", "amd64", "x86_64"] ->
        "windows-x86_64"

      _ ->
        Mix.raise("Unsupported Egglog platform: #{inspect(os)} / #{arch}. See MULTIPLATFORM.md")
    end
  end
end
