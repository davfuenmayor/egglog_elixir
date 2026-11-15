# Real renderer smoke checks, portable across the native CI matrix.
Egglog.Program.with_program("(datatype E (N i64))\n(N 1)", fn program ->
  if System.find_executable("dot") do
    svg = Egglog.Program.snapshot!(program, "", render: :svg)
    true = String.contains?(svg.svg, "<svg")
    :svg = Egglog.Program.snapshot!(program, "", render: :auto).format
  end

  variables = ~w(PATH EGGLOG_GRAPHVIZ_DOT GRAPHVIZ_DOT)
  saved = Map.new(variables, &{&1, System.get_env(&1)})

  try do
    Enum.each(variables, &System.delete_env/1)
    System.put_env("PATH", "")
    mermaid = Egglog.Program.snapshot!(program, "", render: :auto)
    :mermaid = mermaid.format
    true = String.contains?(mermaid.mermaid, "flowchart")
  after
    Enum.each(saved, fn
      {key, nil} -> System.delete_env(key)
      {key, value} -> System.put_env(key, value)
    end)
  end
end)

IO.puts("PASS automatic Mermaid fallback (and Graphviz SVG when installed)")
