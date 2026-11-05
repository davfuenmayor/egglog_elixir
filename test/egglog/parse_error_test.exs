defmodule Egglog.ParseErrorTest do
  use ExUnit.Case, async: true

  alias Egglog.{Commands, EGraph, Native, Program}

  @source "; 🧬\n  )"
  @location %{
    file: nil,
    start_byte: 9,
    end_byte: 10,
    start_line: 2,
    start_column: 3,
    end_line: 2,
    end_column: 4
  }

  test "parsing and loading preserve native messages and structured spans" do
    for parse <- [
          &Egglog.parse/1,
          &Program.parse/1,
          &Commands.parse/1,
          &Program.load/1,
          &EGraph.new/1
        ] do
      assert {:error, {:invalid_theory, message, @location}} = parse.(@source)
      assert message =~ "parse error: unexpected `)`"
      assert message =~ "In 2:3-3"
    end

    # The NIF exposes the structured error without Elixir parsing its text.
    assert {:error, {:invalid_theory, _, @location}} = Native.parse_program(@source)
  end

  test "program execution and inspection propagate parser locations" do
    Program.with_program("(function f (i64) i64 :no-merge)", fn program ->
      for operation <- [
            fn -> Program.run(program, @source) end,
            fn -> Program.snapshot(program, @source, render: :json) end,
            fn -> Program.eval(program, "", @source) end,
            fn -> Program.lookup(program, "", "f", [@source]) end,
            fn -> Program.query(program, "", [], [@source]) end
          ] do
        assert {:error, {:native_error, message, @location}} = operation.()
        assert message =~ "parse error:"
      end

      assert %{value: 3} = Program.eval!(program, "", "(+ 1 2)")
    end)
  end

  test "mutable execution and inspection propagate parser locations and remain usable" do
    EGraph.with_egraph("(function f (i64) i64 :no-merge)", fn graph ->
      for operation <- [
            fn -> EGraph.run(graph, @source) end,
            fn -> EGraph.eval(graph, @source) end,
            fn -> EGraph.lookup(graph, "f", [@source]) end,
            fn -> EGraph.query(graph, [], [@source]) end
          ] do
        assert {:error, {:native_error, _, @location}} = operation.()
      end

      assert %{value: 3} = EGraph.eval!(graph, "(+ 1 2)")
    end)
  end

  test "unexpected EOF is an empty range at the end of the source" do
    source = "; café\r\n(run 1"
    size = byte_size(source)
    assert {:error, {:invalid_theory, message, location}} = Egglog.parse(source)
    assert message =~ "unexpected end of file"

    assert location == %{
             file: nil,
             start_byte: size,
             end_byte: size,
             start_line: 2,
             start_column: 7,
             end_line: 2,
             end_column: 7
           }
  end

  test "multiline string spans have exclusive ends and Unicode character columns" do
    source = "(let x \"a\nβ"
    assert {:error, {:invalid_theory, message, location}} = Egglog.parse(source)
    assert message =~ "string is missing end quote"

    assert location == %{
             file: nil,
             start_byte: 7,
             end_byte: byte_size(source),
             start_line: 1,
             start_column: 8,
             end_line: 2,
             end_column: 2
           }
  end

  test "included-file parser errors retain the filename and file-relative offsets" do
    path = Path.join(System.tmp_dir!(), "egglog-parse-#{System.unique_integer([:positive])}.egg")
    File.write!(path, @source)
    on_exit(fn -> File.rm!(path) end)
    source = "(include #{inspect(path)})"
    expected = %{@location | file: path}

    assert {:error, {:invalid_theory, _, ^expected}} = Program.load(source)

    Program.with_program("", fn program ->
      assert {:error, {:native_error, _, ^expected}} = Program.run(program, source)
      commands = Egglog.parse!(source)
      assert {:error, {:native_error, _, ^expected}} = Program.run(program, commands)
    end)

    EGraph.with_egraph("", fn graph ->
      assert {:error, {:native_error, _, ^expected}} = EGraph.run(graph, source)
      assert {:error, {:native_error, _, ^expected}} = EGraph.run(graph, Egglog.parse!(source))
    end)
  end

  test "command grammar errors also expose a source range" do
    source = "(run)"
    assert {:error, {:invalid_theory, message, location}} = Egglog.parse(source)
    assert message =~ "parse error:"
    assert location.start_byte == 0
    assert location.end_byte == byte_size(source)
  end

  test "non-parser errors keep their existing shapes and failed checks remain booleans" do
    Program.with_program("", fn program ->
      assert {:error, {:native_error, message}} = Program.eval(program, "", "missing")
      assert is_binary(message)
      assert {:error, {:check_failed, _}} = Program.run(program, "(check (= 1 2))")
      assert {:ok, false} = Program.check(program, "", "(= 1 2)")
      assert {:ok, true} = Program.check(program, "", "(= 1 1)")
    end)
  end

  test "bang functions include the structured diagnostic" do
    assert_raise RuntimeError, ~r/start_byte: 9/, fn -> Egglog.parse!(@source) end

    Program.with_program("", fn program ->
      assert_raise RuntimeError, ~r/start_column: 3/, fn -> Program.run!(program, @source) end
    end)
  end
end
