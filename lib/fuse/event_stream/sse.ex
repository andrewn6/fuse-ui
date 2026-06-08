defmodule Fuse.EventStream.SSE do
  @moduledoc """
  Pure Server-Sent Events frame parser.

  Concerned only with SSE **framing**, not payload format: given a chunk of bytes
  (which may span or split events arbitrarily), it returns the completed events'
  `data` payloads and the leftover bytes to carry into the next call.

  Usage is incremental — thread the leftover back in as more bytes arrive:

      {payloads, buffer} = SSE.parse(buffer <> chunk)

  fuse's wire format (`fuse/api/sse.go`) is one `id:` line, one `data:` line, and
  a blank-line terminator, with `: keepalive` comment frames every 15s. This
  parser handles the general SSE shape: comment lines (`:`...) and non-`data`
  fields (`id:`, `event:`, …) are ignored, multiple `data:` lines in one event
  are joined with `\\n`, and a frame carrying no data (e.g. a lone keepalive)
  yields nothing.
  """

  @doc """
  Parse accumulated SSE bytes.

  Returns `{payloads, rest}` where `payloads` are the `data` strings of every
  **complete** event (in order) and `rest` is the trailing partial frame to
  prepend to the next chunk.
  """
  @spec parse(binary()) :: {[binary()], binary()}
  def parse(buffer) when is_binary(buffer) do
    {frames, rest} = split_frames(buffer)
    {Enum.flat_map(frames, &frame_data/1), rest}
  end

  # Blank-line event terminator, tolerating LF or CRLF line endings.
  @frame_boundary ~r/\r?\n\r?\n/

  # Split on the blank-line terminator; the final element is the
  # (possibly empty, possibly partial) leftover frame.
  defp split_frames(buffer) do
    case Regex.split(@frame_boundary, buffer) do
      [only] -> {[], only}
      parts -> {Enum.drop(parts, -1), List.last(parts)}
    end
  end

  # A frame's payload is its `data:` lines joined with "\n"; `[]` if it has none.
  defp frame_data(frame) do
    data =
      frame
      |> String.split("\n")
      |> Enum.flat_map(&field/1)

    case data do
      [] -> []
      lines -> [Enum.join(lines, "\n")]
    end
  end

  defp field(line) do
    case String.trim_trailing(line, "\r") do
      ":" <> _comment -> []
      "data:" <> rest -> [strip_leading_space(rest)]
      _other -> []
    end
  end

  defp strip_leading_space(" " <> rest), do: rest
  defp strip_leading_space(rest), do: rest
end
