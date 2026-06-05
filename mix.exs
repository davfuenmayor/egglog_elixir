defmodule EgglogElixir.MixProject do
  use Mix.Project

  def project do
    [
      app: :egglog_elixir,
      version: "0.1.0",
      elixir: "~> 1.19",
      name: "EgglogElixir",
      description: "Thin Elixir wrapper around the native Rust egglog engine.",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false},
      {:rustler, "~> 0.38.0", runtime: false}
    ]
  end

  defp docs do
    [
      main: "Egglog",
      extras: [
        "README.md",
        "CHANGELOG.md",
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
      links: %{
        "Upstream egglog" => "https://github.com/egraphs-good/egglog",
        "Tutorial" => "https://egraphs-good.github.io/egglog-tutorial/"
      },
      files: [
        ".formatter.exs",
        "CHANGELOG.md",
        "LICENSE",
        "README.md",
        "lib",
        "livebooks",
        "mix.exs",
        "native/egglog_nif/Cargo.lock",
        "native/egglog_nif/Cargo.toml",
        "native/egglog_nif/src"
      ]
    ]
  end
end
