# EgglogElixir

[![Native CI](https://github.com/davfuenmayor/egglog_elixir/actions/workflows/native.yml/badge.svg?branch=main)](https://github.com/davfuenmayor/egglog_elixir/actions/workflows/native.yml)
[![Run in Livebook](https://livebook.dev/badge/v1/blue.svg)](https://livebook.dev/run?url=https%3A%2F%2Fgithub.com%2Fdavfuenmayor%2Fegglog_elixir%2Fblob%2Fmain%2Flivebooks%2Findex.livemd)

Use [egglog](https://github.com/egraphs-good/egglog) from Elixir to rewrite
expressions, query relations, and visualize e-graphs.

## Start in Livebook

1. Open Livebook and click **Run in Livebook** above. If you need Livebook, use the [Desktop installer](https://livebook.dev/#install).
2. Choose **Getting Started** to learn the Elixir API, or **Equality Saturation** to start the egglog tutorial.
3. Run the notebook’s **Setup** cell, then run the examples in order. Setup installs the dependencies from Hex and needs internet access on the first run.

> ⚠️ **Graphviz is optional.** When Livebook can find `dot`, it draws SVG graphs
> from egglog’s DOT output. Otherwise it draws Mermaid graphs from egglog’s JSON
> automatically.

Browse the [notebook index](livebooks/index.livemd) or the [Livebook guide](livebooks/README.md).

## Use it in a Mix project

Add this to your dependencies in `mix.exs`:

```elixir
{:egglog_elixir, "0.3.0"}
```

Requires Elixir 1.19+ and 64-bit Erlang/OTP 27+ on macOS (Intel or Apple Silicon),
Windows (x64), or Linux (glibc, x64 or ARM64).

Choose `Egglog.Program` for independent runs from a reusable base, or
`Egglog.EGraph` for a session that keeps its state between calls and supports
`push` and `pop`.

```elixir
rules = """
(datatype Expr (Num i64) (Add Expr Expr))
(rewrite (Add x (Num 0)) x)
"""

input = """
(let expr (Add (Num 7) (Num 0)))
(run 3)
"""

Egglog.Program.with_program(rules, fn program ->
  Egglog.Program.extract!(program, input, "expr")
end)
# => "(Num 7)"
```

[Getting Started](livebooks/getting_started.livemd) compares both execution models
on one arithmetic example and covers typed queries and error handling. See the
[API reference](https://hexdocs.pm/egglog_elixir/) and [changelog](CHANGELOG.md).
