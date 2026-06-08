defmodule Fuse.EventStream.Event do
  @moduledoc """
  A single decoded event from fuse's environment SSE stream
  (`GET /v1/environments/{id}/events`).

  Mirrors fuse's `EnvironmentEvent` wire object. In v1 the only event `kind` is
  `"state"` (carried in the JSON `event` field, not the SSE `event:` line).
  `updated_at` decodes to `DateTime`; `state` is a `Fuse.State` value, with
  `destroyed`/`failed` being terminal and signalling the end of the stream.
  """

  alias Fuse.State
  alias Fuse.Wire

  @type t :: %__MODULE__{
          id: String.t() | nil,
          kind: String.t() | nil,
          vm_id: String.t() | nil,
          state: String.t() | nil,
          url: String.t() | nil,
          error: String.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [:id, :kind, :vm_id, :state, :url, :error, :updated_at]

  @doc "Decode a wire event map (string-keyed, from the `data:` frame) into an `Event`."
  @spec from_wire(map()) :: t()
  def from_wire(map) when is_map(map) do
    %__MODULE__{
      id: map["id"],
      kind: map["event"],
      vm_id: map["vm_id"],
      state: map["state"],
      url: map["url"],
      error: map["error"],
      updated_at: Wire.parse_datetime(map["updated_at"])
    }
  end

  @doc """
  Whether this event is terminal (`destroyed`/`failed`). The stream closes after
  a terminal event, so consumers should stop on it rather than waiting for EOF.
  """
  @spec terminal?(t()) :: boolean()
  def terminal?(%__MODULE__{state: state}), do: State.terminal?(state)
end
