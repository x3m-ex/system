defmodule X3m.System.TelemetryGuideTest do
  use ExUnit.Case, async: true

  @guide "guides/telemetry.md"

  test "the telemetry guide documents every emitted event" do
    emitted =
      "lib/**/*.ex"
      |> Path.wildcard()
      |> Enum.flat_map(&_emitted_events/1)
      |> Enum.uniq()

    assert length(emitted) > 10, "expected to find the emitted events, found #{inspect(emitted)}"

    guide = File.read!(@guide)
    undocumented = Enum.reject(emitted, &String.contains?(guide, "| `:#{&1}` |"))

    assert [] == undocumented
  end

  defp _emitted_events(path) do
    ~r/Instrumenter\.execute\(\s*:(\w+)/
    |> Regex.scan(File.read!(path), capture: :all_but_first)
    |> List.flatten()
  end
end
