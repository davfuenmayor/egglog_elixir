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
      extra_applications: [:logger, :crypto]
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
        "MULTIPLATFORM.md",
        "livebooks/README.md",
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
        "MULTIPLATFORM.md",
        "native/precompiled",
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
    if Application.get_env(:egglog_elixir, :build_from_source, false) or
         System.get_env("EGGLOG_BUILD") in ["1", "true"] or
         System.get_env("RUSTLER_PRECOMPILED_FORCE_BUILD_ALL") in ["1", "true"] do
      {output, status} = System.cmd("bash", ["scripts/build_native.sh"], stderr_to_stdout: true)
      if status != 0, do: Mix.raise(output)
      Mix.shell().info(output)
    end

    if :erlang.system_info(:wordsize) != 8,
      do: Mix.raise("egglog_elixir requires a 64-bit Erlang runtime")

    os = :os.type()

    arch =
      if os == {:win32, :nt},
        do: System.get_env("PROCESSOR_ARCHITECTURE", "unknown"),
        else: to_string(:erlang.system_info(:system_architecture))

    target = target(os, arch)

    archive =
      System.get_env("EGGLOG_ELIXIR_BUNDLE") ||
        "native/precompiled/egglog-#{Mix.Project.config()[:version]}-#{target}.tar.gz"

    unless File.regular?(archive),
      do:
        Mix.raise(
          "Missing #{target} Egglog bundle. See MULTIPLATFORM.md; EGGLOG_BUILD=1 enables a local Rust build."
        )

    {:ok, _} = Application.ensure_all_started(:crypto)
    expected = File.read!(archive <> ".sha256") |> String.trim()
    actual = :crypto.hash(:sha256, File.read!(archive)) |> Base.encode16(case: :lower)
    if actual != expected, do: Mix.raise("Egglog native archive checksum mismatch")
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
