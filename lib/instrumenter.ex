defmodule X3m.System.Instrumenter do
  @spec execute(atom, map, map) :: :ok
  def execute(name, measurements \\ %{}, data \\ %{}),
    do: :telemetry.execute([:x3m, :system, name], measurements, data)

  @spec duration(integer, System.time_unit() | :native) :: integer
  def duration(mono_start, unit) do
    mono_time = System.monotonic_time()

    (mono_time - mono_start)
    |> System.convert_time_unit(:nanosecond, unit)
  end
end
