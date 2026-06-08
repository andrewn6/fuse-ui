defmodule Fuse.Hosts.Host do
  @moduledoc """
  A decoded fuse host (worker node), mirroring fuse's `HostInfo` wire object.

  `capacity` and `allocated` decode into `Capacity` structs; timestamps
  (`last_seen`, `created_at`, `updated_at`) into `DateTime`. State is one of
  `active` / `cordoned` / `draining`; use the thin `active?/1` / `cordoned?/1` /
  `draining?/1` helpers here.
  """

  defmodule Capacity do
    @moduledoc "Resource counts for a host (used for both `capacity` and `allocated`)."

    @type t :: %__MODULE__{
            cpus: integer() | nil,
            ram_mb: integer() | nil,
            storage_gb: integer() | nil,
            vm_count: integer() | nil
          }

    defstruct [:cpus, :ram_mb, :storage_gb, :vm_count]

    @doc "Decode a wire capacity map (string-keyed) into a `Capacity` struct."
    @spec from_wire(map()) :: t()
    def from_wire(map) when is_map(map) do
      %__MODULE__{
        cpus: map["cpus"],
        ram_mb: map["ram_mb"],
        storage_gb: map["storage_gb"],
        vm_count: map["vm_count"]
      }
    end
  end

  @type t :: %__MODULE__{
          id: String.t(),
          url: String.t() | nil,
          region: String.t() | nil,
          state: String.t() | nil,
          capacity: Capacity.t() | nil,
          allocated: Capacity.t() | nil,
          last_seen: DateTime.t() | nil,
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [
    :id,
    :url,
    :region,
    :state,
    :capacity,
    :allocated,
    :last_seen,
    :created_at,
    :updated_at
  ]

  @doc "Decode a wire JSON map (string-keyed) into a `Host` struct."
  @spec from_wire(map()) :: t()
  def from_wire(map) when is_map(map) do
    %__MODULE__{
      id: map["id"],
      url: map["url"],
      region: map["region"],
      state: map["state"],
      capacity: decode_capacity(map["capacity"]),
      allocated: decode_capacity(map["allocated"]),
      last_seen: Fuse.Wire.parse_datetime(map["last_seen"]),
      created_at: Fuse.Wire.parse_datetime(map["created_at"]),
      updated_at: Fuse.Wire.parse_datetime(map["updated_at"])
    }
  end

  @doc "Whether the host is `active` (schedulable)."
  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{state: state}), do: state == "active"

  @doc "Whether the host is `cordoned` (no new placements)."
  @spec cordoned?(t()) :: boolean()
  def cordoned?(%__MODULE__{state: state}), do: state == "cordoned"

  @doc "Whether the host is `draining` (existing VMs migrating off)."
  @spec draining?(t()) :: boolean()
  def draining?(%__MODULE__{state: state}), do: state == "draining"

  defp decode_capacity(map) when is_map(map), do: Capacity.from_wire(map)
  defp decode_capacity(_other), do: nil
end
