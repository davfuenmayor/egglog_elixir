defmodule Egglog.Program.StepTest do
  use ExUnit.Case, async: true

  alias Egglog.Program.Step

  test "replays and branches without changing earlier steps or retaining earlier output" do
    initial = Step.new("(relation seen (i64))\n(extract 100)")
    first = Step.next(initial, "(seen 1)\n(extract 1)", render: :json)
    second = Step.next(first, "(seen 2)\n(extract 2)", render: :json)
    branch = Step.next(first, "(fail (check (seen 2)))\n(check (seen 1))", render: :json)
    replay = Step.next(initial, "(seen 1)\n(extract 1)", render: :json)

    assert initial.snapshot == nil
    assert first.source == replay.source
    assert Egglog.Output.texts(first.snapshot.result) == ["1"]
    assert Egglog.Output.texts(second.snapshot.result) == ["2"]
    assert branch.snapshot.format == :json
    assert second.source != branch.source
    assert is_binary(first.snapshot.json)
    refute inspect(second) =~ "(seen"
  end

  test "native push/pop history survives step reconstruction" do
    initial = Step.new()
    saved = Step.next(initial, "(push)", render: :json)
    populated = Step.next(saved, "(relation seen (i64))\n(seen 1)", render: :json)
    restored = Step.next(populated, "(pop)", render: :json)
    redefined = Step.next(restored, "(relation seen (String))\n(seen \"x\")", render: :json)

    assert populated.snapshot.stats.snapshot_nodes > 0
    assert restored.snapshot.stats.snapshot_nodes == 0
    assert redefined.snapshot.stats.snapshot_nodes > 0
  end

  test "a failed step leaves its predecessor usable" do
    initial = Step.new("(relation seen (i64))")

    assert_raise RuntimeError, ~r/failed to execute program step/, fn ->
      Step.next(initial, "(seen 1)\n(check (seen 2))", render: :json)
    end

    next = Step.next(initial, "(fail (check (seen 1)))\n(seen 3)", render: :json)
    assert next.snapshot.stats.snapshot_nodes > 0
    assert initial.snapshot == nil

    assert_raise RuntimeError, ~r/failed to execute program step/, fn ->
      Step.next(Step.new("(invalid-command)"), "", render: :json)
    end
  end

  test "snapshot rendering options are forwarded and invalid options fail" do
    step = Step.next(Step.new(), "(datatype E (N i64))\n(N 1)", render: :mermaid)
    assert step.snapshot.format == :mermaid
    assert step.snapshot.mermaid =~ "flowchart"
    assert is_binary(step.snapshot.json)

    assert_raise RuntimeError, ~r/invalid_option/, fn ->
      Step.next(step, "", render: :invalid)
    end
  end
end
