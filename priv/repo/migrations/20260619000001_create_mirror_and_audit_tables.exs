defmodule Fuse.Repo.Migrations.CreateMirrorAndAuditTables do
  use Ecto.Migration

  def change do
    # Local read-model cache of fuse environments. fuse stays authoritative; this
    # is populated write-through from list/get and from SSE events, for audit and
    # offline inspection. The id is fuse's environment id (the natural key).
    create table(:mirror_environments, primary_key: false) do
      add :id, :string, primary_key: true
      add :task_id, :string
      add :host_id, :string
      add :state, :string
      add :url, :string
      add :error, :string
      add :cpus, :integer
      add :ram_mb, :integer
      add :storage_gb, :integer
      add :region, :string
      add :max_runtime_seconds, :integer
      add :fuse_created_at, :utc_datetime
      add :fuse_updated_at, :utc_datetime
      add :synced_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:mirror_environments, [:state])
    create index(:mirror_environments, [:task_id])
    create index(:mirror_environments, [:host_id])

    create table(:mirror_snapshots, primary_key: false) do
      add :id, :string, primary_key: true
      add :vm_id, :string
      add :task_id, :string
      add :tenant_id, :string
      add :state, :string
      add :mode, :string
      add :comment, :string
      add :size_bytes, :integer
      add :fuse_created_at, :utc_datetime
      add :synced_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:mirror_snapshots, [:vm_id])
    create index(:mirror_snapshots, [:state])

    # Append-only audit trail of mutating actions (who/what/when).
    create table(:audit_log) do
      add :action, :string, null: false
      add :resource_type, :string, null: false
      add :resource_id, :string
      add :actor, :string
      add :metadata, :map
      add :result, :string
      add :occurred_at, :utc_datetime_usec, null: false
    end

    create index(:audit_log, [:resource_type, :resource_id])
    create index(:audit_log, [:occurred_at])
  end
end
