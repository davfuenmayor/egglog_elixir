defmodule Egglog.OutputTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO
  alias Egglog.{EGraph, Output}

  test "native text preserves order and can be filtered without inventing output" do
    result = %{
      outputs: [
        %{type: :extract, text: "(Num 1)\n"},
        %{type: :print_function, text: "rows\n\n"},
        %{type: :extract, text: nil},
        %{type: :extract, text: ""}
      ]
    }

    assert Output.texts(result) == ["(Num 1)", "rows"]
    assert Output.texts(result, :extract) == ["(Num 1)"]
    assert capture_io(fn -> assert :ok = Output.print(result) end) == "(Num 1)\nrows\n"
    assert capture_io(fn -> Output.print(result, :extract) end) == "(Num 1)\n"
    assert capture_io(fn -> Output.print(%{outputs: []}) end) == ""
  end

  test "checks and misleading source comments produce only native output" do
    EGraph.with_egraph(fn graph ->
      result =
        EGraph.run!(graph, """
        ; (check (= 1 2)) is only a comment
        (check
          (= 1 1))
        (fail (check (= 1 2)))
        (extract 42)
        """)

      printed = capture_io(fn -> Output.print(result) end)
      assert printed =~ "42"
      refute printed =~ "check succeeded:"
      refute printed =~ "expected failure observed:"
      refute printed =~ "only a comment"
    end)
  end
end
