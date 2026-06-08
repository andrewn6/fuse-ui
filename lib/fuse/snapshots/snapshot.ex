defmodule Fuse.Snapshots.Snapshot do
  @moduledoc """
  A decoded fuse snapshot, mirroring fuse's `Snapshot` wire object, including
  the nested `exports`. Timestamps (`created_at`, `updated_at`, `retention_until`)
  decode to `DateTime`. Use `Fuse.SnapshotState` for state predicates, or the
  thin `ready?/1` / `error?/1` helpers here.
  """

  alias Fuse.SnapshotState

  defmodule Export do
    @moduledoc "A single export destination attached to a snapshot."

    @type t :: %__MODULE__{
            destination: String.t() | nil,
            status: String.t() | nil,
            requested_at: DateTime.t() | nil,
            updated_at: DateTime.t() | nil,
            last_error: String.t() | nil
          }

    defstruct [:destination, :status, :requested_at, :updated_at, :last_error]

    @doc "Decode a wire export map into an `Export` struct."
    @spec from_wire(map()) :: t()
    def from_wire(map) when is_map(map) do
      %__MODULE__{
        destination: map["destination"],
        status: map["status"],
        requested_at: parse_datetime(map["requested_at"]),
        updated_at: parse_datetime(map["updated_at"]),
        last_error: map["last_error"]
      }
    end

    defp parse_datetime(value) when is_binary(value) do
      case DateTime.from_iso8601(value) do
        {:ok, datetime, _offset} -> datetime
        {:error, _reason} -> nil
      end
    end

    defp parse_datetime(_value), do: nil
  end

  @type t :: %__MODULE__{
          id: String.t(),
          vm_id: String.t() | nil,
          task_id: String.t() | nil,
          tenant_id: String.t() | nil,
          parent_snapshot_id: String.t() | nil,
          mode: String.t() | nil,
          state: String.t() | nil,
          comment: String.t() | nil,
          size_bytes: non_neg_integer() | nil,
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil,
          retention_until: DateTime.t() | nil,
          last_error: String.t() | nil,
          export_ref: String.t() | nil,
          exports: [Export.t()]
        }

  defstruct [
    :id,
    :vm_id,
    :task_id,
    :tenant_id,
    :parent_snapshot_id,
    :mode,
    :state,
    :comment,
    :size_bytes,
    :created_at,
    :updated_at,
    :retention_until,
    :last_error,
    :export_ref,
    exports: []
  ]

  @doc "Decode a wire JSON map (string-keyed) into a `Snapshot` struct."
  @spec from_wire(map()) :: t()
  def from_wire(map) when is_map(map) do
    %__MODULE__{
      id: map["id"],
      vm_id: map["vm_id"],
      task_id: map["task_id"],
      tenant_id: map["tenant_id"],
      parent_snapshot_id: map["parent_snapshot_id"],
      mode: map["mode"],
      state: map["state"],
      comment: map["comment"],
      size_bytes: map["size_bytes"],
      created_at: parse_datetime(map["created_at"]),
      updated_at: parse_datetime(map["updated_at"]),
      retention_until: parse_datetime(map["retention_until"]),
      last_error: map["last_error"],
      export_ref: map["export_ref"],
      exports: decode_exports(map["exports"])
    }
  end

  @doc "Whether the snapshot is `ready` (safe to restore or export from)."
  @spec ready?(t()) :: boolean()
  def ready?(%__MODULE__{state: state}), do: SnapshotState.ready?(state)

  @doc "Whether the snapshot is in the `error` state."
  @spec error?(t()) :: boolean()
  def error?(%__MODULE__{state: state}), do: SnapshotState.error?(state)

  defp decode_exports(list) when is_list(list), do: Enum.map(list, &Export.from_wire/1)
  defp decode_exports(_other), do: []

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> nil
    end
  end

  defp parse_datetime(_value), do: nil
end
