defmodule Fuse.Mirror.Environment do
  @moduledoc """
  Ecto schema for the local read-model cache of a fuse environment.

  This is a *cache*, not the source of truth — fuse remains authoritative. Rows
  are upserted write-through from `Fuse.Environments` list/get and patched from
  SSE events via `Fuse.Mirror`. The primary key is fuse's environment id.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  schema "mirror_environments" do
    field :task_id, :string
    field :host_id, :string
    field :state, :string
    field :url, :string
    field :error, :string
    field :cpus, :integer
    field :ram_mb, :integer
    field :storage_gb, :integer
    field :region, :string
    field :max_runtime_seconds, :integer
    field :fuse_created_at, :utc_datetime
    field :fuse_updated_at, :utc_datetime
    field :synced_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @fields ~w(id task_id host_id state url error cpus ram_mb storage_gb region
             max_runtime_seconds fuse_created_at fuse_updated_at synced_at)a

  @doc false
  def changeset(env, attrs) do
    env
    |> cast(attrs, @fields)
    |> validate_required([:id])
  end
end
