defmodule Fuse.Mirror.Snapshot do
  @moduledoc """
  Ecto schema for the local read-model cache of a fuse snapshot. A cache only —
  fuse stays authoritative. Upserted write-through from `Fuse.Snapshots`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  schema "mirror_snapshots" do
    field :vm_id, :string
    field :task_id, :string
    field :tenant_id, :string
    field :state, :string
    field :mode, :string
    field :comment, :string
    field :size_bytes, :integer
    field :fuse_created_at, :utc_datetime
    field :synced_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @fields ~w(id vm_id task_id tenant_id state mode comment size_bytes
             fuse_created_at synced_at)a

  @doc false
  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, @fields)
    |> validate_required([:id])
  end
end
