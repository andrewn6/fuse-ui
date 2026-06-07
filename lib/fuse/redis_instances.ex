defmodule Fuse.RedisInstances do
  @moduledoc """
  Manages Redis instances that will be backed by Docker containers.
  """

  import Ecto.Query, warn: false

  alias Fuse.Repo
  alias Fuse.RedisInstances.RedisInstance

  def list_redis_instances do
    Repo.all(from instance in RedisInstance, order_by: [asc: instance.name])
  end

  def get_redis_instance!(id), do: Repo.get!(RedisInstance, id)

  def create_redis_instance(attrs \\ %{}) do
    %RedisInstance{}
    |> RedisInstance.changeset(attrs)
    |> Repo.insert()
  end

  def update_redis_instance(%RedisInstance{} = redis_instance, attrs) do
    redis_instance
    |> RedisInstance.changeset(attrs)
    |> Repo.update()
  end

  def delete_redis_instance(%RedisInstance{} = redis_instance) do
    Repo.delete(redis_instance)
  end

  def change_redis_instance(%RedisInstance{} = redis_instance, attrs \\ %{}) do
    RedisInstance.changeset(redis_instance, attrs)
  end
end
