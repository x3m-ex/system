defmodule X3m.System.UuidTest do
  use ExUnit.Case, async: true

  alias X3m.System.Uuid

  @samples 1_000

  describe "v7/0" do
    test "returns a lowercase, hyphenated 36-character string" do
      uuids = Enum.map(1..@samples, fn _sample -> Uuid.v7() end)

      well_formed? =
        uuids
        |> Enum.all?(
          &(&1 =~ ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
        )

      assert true == well_formed?
    end

    test "sets the version to 7" do
      versions =
        1..@samples
        |> Enum.map(fn _sample -> Uuid.v7() |> String.at(14) end)
        |> Enum.uniq()

      assert ["7"] == versions
    end

    test "sets the RFC 9562 variant" do
      variants =
        1..@samples
        |> Enum.map(fn _sample -> Uuid.v7() |> String.at(19) end)
        |> Enum.uniq()
        |> Enum.sort()

      assert [] == variants -- ["8", "9", "a", "b"]
      assert [] != variants
    end

    test "starts with the generation time in Unix milliseconds" do
      before_ms = System.os_time(:millisecond)
      uuid = Uuid.v7()
      after_ms = System.os_time(:millisecond)

      timestamp_ms =
        uuid
        |> String.replace("-", "")
        |> String.slice(0, 12)
        |> String.to_integer(16)

      assert timestamp_ms in before_ms..after_ms
    end

    test "sorts ids generated in successive milliseconds in generation order" do
      earlier = Uuid.v7()
      :ok = _await_next_millisecond(System.os_time(:millisecond))
      later = Uuid.v7()

      assert [earlier, later] == Enum.sort([later, earlier])
    end

    test "returns a different id every time" do
      uuids = Enum.map(1..@samples, fn _sample -> Uuid.v7() end)

      unique_count =
        uuids
        |> Enum.uniq()
        |> length()

      assert @samples == unique_count
    end
  end

  defp _await_next_millisecond(now_ms) do
    if System.os_time(:millisecond) > now_ms,
      do: :ok,
      else: _await_next_millisecond(now_ms)
  end
end
