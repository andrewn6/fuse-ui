defmodule Fuse.Wire do
  @moduledoc """
  Shared decoders for fuse wire (JSON) values.

  Keeps the lenient "parse what fuse sends, fall back to `nil`" conventions in
  one place so the struct decoders (`Environment`, `Snapshot`, `Host`, SSE
  `Event`, …) stay uniform.
  """

  @doc """
  Parse an ISO-8601 / RFC 3339 timestamp string into a `DateTime`.

  Non-binary or unparseable input yields `nil` rather than raising — wire data
  is decoded leniently.
  """
  @spec parse_datetime(term()) :: DateTime.t() | nil
  def parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> nil
    end
  end

  def parse_datetime(_value), do: nil
end
