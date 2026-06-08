defmodule Fuse.Environments.Environment do
  @moduledoc """
  A decoded fuse environment (microVM).

  Mirrors fuse's `Environment` wire object. `spec` is decoded into a
  `Fuse.ResourceSpec`; `created_at`/`updated_at` into `DateTime`. Use
  `Fuse.State` for state predicates, or the thin `running?/1` / `terminal?/1`
  helpers here.
  """

  alias Fuse.ResourceSpec
  alias Fuse.State
  alias Fuse.Wire

  @type t :: %__MODULE__{
          id: String.t(),
          state: String.t() | nil,
          task_id: String.t() | nil,
          host_id: String.t() | nil,
          url: String.t() | nil,
          spec: ResourceSpec.t() | nil,
          error: String.t() | nil,
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [:id, :state, :task_id, :host_id, :url, :spec, :error, :created_at, :updated_at]

  @doc "Decode a wire JSON map (string-keyed) into an `Environment` struct."
  @spec from_wire(map()) :: t()
  def from_wire(map) when is_map(map) do
    %__MODULE__{
      id: map["id"],
      state: map["state"],
      task_id: map["task_id"],
      host_id: map["host_id"],
      url: map["url"],
      spec: decode_spec(map["spec"]),
      error: map["error"],
      created_at: Wire.parse_datetime(map["created_at"]),
      updated_at: Wire.parse_datetime(map["updated_at"])
    }
  end

  @doc "Whether the environment is in the `running` state."
  @spec running?(t()) :: boolean()
  def running?(%__MODULE__{state: state}), do: State.running?(state)

  @doc "Whether the environment is in a terminal state (`destroyed`/`failed`)."
  @spec terminal?(t()) :: boolean()
  def terminal?(%__MODULE__{state: state}), do: State.terminal?(state)

  defp decode_spec(spec) when is_map(spec), do: ResourceSpec.from_wire(spec)
  defp decode_spec(_), do: nil
end
