defmodule Fuse.Repo.Migrations.CreateRedisInstances do
  use Ecto.Migration

  def change do
    create table(:redis_instances) do
      add :name, :string, null: false
      add :docker_container_id, :string
      add :docker_container_name, :string
      add :image, :string, null: false, default: "redis:7-alpine"
      add :host, :string, null: false, default: "127.0.0.1"
      add :port, :integer
      add :memory_mb, :integer, null: false, default: 256
      add :cpu_limit, :float, null: false, default: 0.25
      add :status, :string, null: false, default: "created"
      add :last_seen_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:redis_instances, [:name])
    create unique_index(:redis_instances, [:docker_container_id])
    create unique_index(:redis_instances, [:docker_container_name])
  end
end
