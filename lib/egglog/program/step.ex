defmodule Egglog.Program.Step do
  @moduledoc """
  Replayable steps of an egglog program, with a snapshot after each step.

  A `Step` names a point in the program's execution history. `new/1` creates
  step zero; `next/3` constructs a following step without changing its predecessor.

  A step is ordinary data: `source` is the accumulated egglog source and
  `snapshot` is the retained result of the latest step. It owns no native handle
  and has no dependency on Kino. Steps can be revisited or used as branch points.

      initial = Egglog.Program.Step.new("(relation seen (i64))")
      first = Egglog.Program.Step.next(initial, "(seen 1)", render: :json)
      second = Egglog.Program.Step.next(first, "(seen 2)", render: :json)

  Each step reexecutes its predecessor's source in a scoped `Egglog.Program`,
  executes the new code on a clone, captures its snapshot, and closes the handle.
  Earlier steps remain unchanged. Native push/pop commands retain their normal
  meaning within that reconstructed history. Replay can repeat expensive work
  and external effects such as native file writes.

  Notebook setup can implement `Kino.Render` for this struct to display native
  output and the snapshot automatically; the library itself only returns data.
  """

  defstruct source: "", snapshot: nil

  @doc """
  Creates an initial step, optionally with egglog source.

  Returns ordinary data without starting a process or native session. Source is
  executed only by `next/3`. The initial step has no snapshot.
  """
  def new(source \\ "") when is_binary(source), do: %__MODULE__{source: source}

  @doc """
  Executes `code` after `previous` and returns a new step with its snapshot.

  Accepts the snapshot options of `Egglog.Program.snapshot/3`, including
  `render: :auto` (the default), serialization limits, and artifact paths.
  Only the current step's native output is retained in `snapshot.result`.
  Rendering the returned data does not rerun egglog.

  Raises on load, execution, rendering or option errors, matching
  `Egglog.Program.snapshot!/3`. Failure leaves `previous` unchanged and closes
  any native handle opened for the step.
  """
  def next(%__MODULE__{} = previous, code, opts \\ []) when is_binary(code) do
    snapshot =
      Egglog.Program.with_program(previous.source, fn program ->
        Egglog.Program.snapshot(program, code, opts)
      end)
      |> Egglog.Common.bang("failed to execute program step")

    %__MODULE__{source: previous.source <> "\n" <> code, snapshot: snapshot}
  end
end

defimpl Inspect, for: Egglog.Program.Step do
  import Inspect.Algebra

  def inspect(step, opts) do
    format = if step.snapshot, do: step.snapshot.format, else: nil

    concat([
      "#Egglog.Program.Step<",
      to_doc([source_bytes: byte_size(step.source), snapshot: format], opts),
      ">"
    ])
  end
end
