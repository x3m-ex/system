defmodule X3m.System.Instrumenter do
  @moduledoc !"""
             Internal. Thin wrapper over `:telemetry.execute/3` for the `[:x3m, :system, _]`
             event prefix, plus a monotonic-duration helper.
             """
  @spec execute(atom, map, map) :: :ok
  def execute(name, measurements \\ %{}, data \\ %{}),
    do: :telemetry.execute([:x3m, :system, name], measurements, data)

  @spec duration(integer) :: integer
  def duration(mono_start),
    do: System.monotonic_time() - mono_start
end
