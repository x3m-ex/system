defmodule X3m.System.Uuid do
  @moduledoc !"""
             Internal. Generates time-ordered (version 7, RFC 9562) UUIDs, so ids need no
             extra dependency and index well: ids created later sort after earlier ones.
             """

  @doc "Returns an RFC 9562 version 7 UUID as a lowercase, hyphenated string."
  @spec v7() :: uuid :: String.t()
  def v7 do
    <<_unused::48, _version::4, rand_a::12, _variant::2, rand_b::62>> =
      :crypto.strong_rand_bytes(16)

    timestamp_ms = System.os_time(:millisecond)

    <<timestamp_ms::48, 7::4, rand_a::12, 2::2, rand_b::62>>
    |> Base.encode16(case: :lower)
    |> _hyphenate()
  end

  defp _hyphenate(<<a::binary-8, b::binary-4, c::binary-4, d::binary-4, e::binary-12>>),
    do: Enum.join([a, b, c, d, e], "-")
end
