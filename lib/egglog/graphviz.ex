defmodule Egglog.Graphviz do
  @moduledoc false

  def render(input, output, timeout) do
    executable = System.find_executable("dot")

    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: ["-Tsvg", input, "-o", output]
      ])

    try do
      await(port, System.monotonic_time(:millisecond) + timeout, [], timeout)
    after
      stop(port)
    end
  end

  defp await(port, deadline, chunks, timeout) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    if remaining == 0 do
      {:error, {:graphviz_timeout, timeout}}
    else
      receive do
        {^port, {:data, data}} ->
          await(port, deadline, [data | chunks], timeout)

        {^port, {:exit_status, 0}} ->
          {:ok, chunks |> Enum.reverse() |> IO.iodata_to_binary()}

        {^port, {:exit_status, status}} ->
          {:error, {:graphviz_failed, status, chunks |> Enum.reverse() |> IO.iodata_to_binary()}}
      after
        remaining -> {:error, {:graphviz_timeout, timeout}}
      end
    end
  end

  defp stop(port) do
    # Closing a port alone does not reliably terminate a CPU-bound Graphviz
    # process. Kill the directly spawned renderer before closing its pipes.
    case Port.info(port, :os_pid) do
      {:os_pid, pid} ->
        case :os.type() do
          {:win32, _} ->
            System.cmd("taskkill", ["/PID", to_string(pid), "/T", "/F"], stderr_to_stdout: true)

          {:unix, _} ->
            System.cmd("kill", ["-KILL", to_string(pid)], stderr_to_stdout: true)
        end

        close(port)

      nil ->
        :ok
    end
  end

  defp close(port) do
    Port.close(port)
  rescue
    ArgumentError -> :ok
  end
end
