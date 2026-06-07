defmodule Fuse.RedisInstancesTest do
  use Fuse.DataCase, async: false

  alias Fuse.RedisInstances
  alias Fuse.RedisInstances.RedisInstance

  @valid_attrs %{
    name: "primary_queue",
    docker_container_id: "container-123",
    docker_container_name: "fuse-redis-primary_queue",
    image: "redis:7-alpine",
    host: "127.0.0.1",
    port: 6_379,
    memory_mb: 256,
    cpu_limit: 0.25,
    status: "created"
  }

  @invalid_attrs %{
    name: "no spaces allowed",
    port: 70_000,
    memory_mb: 64,
    cpu_limit: 0.01,
    status: "unknown"
  }

  describe "redis_instances" do
    test "list_redis_instances/0 returns redis instances ordered by name" do
      {:ok, second} = RedisInstances.create_redis_instance(%{name: "second"})
      {:ok, first} = RedisInstances.create_redis_instance(%{name: "first"})

      assert RedisInstances.list_redis_instances() == [first, second]
    end

    test "get_redis_instance!/1 returns the redis instance with given id" do
      {:ok, redis_instance} = RedisInstances.create_redis_instance(@valid_attrs)

      assert RedisInstances.get_redis_instance!(redis_instance.id) == redis_instance
    end

    test "create_redis_instance/1 with valid data creates a redis instance" do
      assert {:ok, %RedisInstance{} = redis_instance} =
               RedisInstances.create_redis_instance(@valid_attrs)

      assert redis_instance.name == "primary_queue"
      assert redis_instance.docker_container_id == "container-123"
      assert redis_instance.docker_container_name == "fuse-redis-primary_queue"
      assert redis_instance.image == "redis:7-alpine"
      assert redis_instance.host == "127.0.0.1"
      assert redis_instance.port == 6_379
      assert redis_instance.memory_mb == 256
      assert redis_instance.cpu_limit == 0.25
      assert redis_instance.status == "created"
    end

    test "create_redis_instance/1 applies defaults" do
      assert {:ok, %RedisInstance{} = redis_instance} =
               RedisInstances.create_redis_instance(%{name: "defaulted"})

      assert redis_instance.docker_container_name == "fuse-redis-defaulted"
      assert redis_instance.image == "redis:7-alpine"
      assert redis_instance.host == "127.0.0.1"
      assert redis_instance.memory_mb == 256
      assert redis_instance.cpu_limit == 0.25
      assert redis_instance.status == "created"
    end

    test "create_redis_instance/1 preserves explicit docker container names" do
      assert {:ok, %RedisInstance{} = redis_instance} =
               RedisInstances.create_redis_instance(%{
                 name: "explicit",
                 docker_container_name: "custom-redis-name"
               })

      assert redis_instance.docker_container_name == "custom-redis-name"
    end

    test "create_redis_instance/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{} = changeset} =
               RedisInstances.create_redis_instance(@invalid_attrs)

      assert "has invalid format" in errors_on(changeset).name
      assert "must be less than or equal to 65535" in errors_on(changeset).port
      assert "must be greater than or equal to 128" in errors_on(changeset).memory_mb
      assert "must be greater than or equal to 0.1" in errors_on(changeset).cpu_limit
      assert "is invalid" in errors_on(changeset).status
    end

    test "create_redis_instance/1 requires unique names" do
      attrs = %{name: "unique_name"}

      assert {:ok, %RedisInstance{}} = RedisInstances.create_redis_instance(attrs)

      assert {:error, changeset} =
               RedisInstances.create_redis_instance(%{
                 name: "unique_name",
                 docker_container_name: "fuse-redis-different-name"
               })

      assert "has already been taken" in errors_on(changeset).name
    end

    test "create_redis_instance/1 requires unique docker container names" do
      attrs = %{name: "unique_docker_name"}

      assert {:ok, %RedisInstance{} = redis_instance} =
               RedisInstances.create_redis_instance(attrs)

      assert {:error, changeset} =
               RedisInstances.create_redis_instance(%{
                 name: "different_instance",
                 docker_container_name: redis_instance.docker_container_name
               })

      assert "has already been taken" in errors_on(changeset).docker_container_name
    end

    test "update_redis_instance/2 with valid data updates the redis instance" do
      {:ok, redis_instance} = RedisInstances.create_redis_instance(@valid_attrs)

      update_attrs = %{
        port: 16_379,
        memory_mb: 512,
        cpu_limit: 0.5,
        status: "running"
      }

      assert {:ok, %RedisInstance{} = redis_instance} =
               RedisInstances.update_redis_instance(redis_instance, update_attrs)

      assert redis_instance.port == 16_379
      assert redis_instance.memory_mb == 512
      assert redis_instance.cpu_limit == 0.5
      assert redis_instance.status == "running"
    end

    test "update_redis_instance/2 with invalid data returns error changeset" do
      {:ok, redis_instance} = RedisInstances.create_redis_instance(@valid_attrs)

      assert {:error, %Ecto.Changeset{}} =
               RedisInstances.update_redis_instance(redis_instance, @invalid_attrs)

      assert redis_instance == RedisInstances.get_redis_instance!(redis_instance.id)
    end

    test "delete_redis_instance/1 deletes the redis instance" do
      {:ok, redis_instance} = RedisInstances.create_redis_instance(@valid_attrs)

      assert {:ok, %RedisInstance{}} = RedisInstances.delete_redis_instance(redis_instance)

      assert_raise Ecto.NoResultsError, fn ->
        RedisInstances.get_redis_instance!(redis_instance.id)
      end
    end

    test "change_redis_instance/1 returns a redis instance changeset" do
      {:ok, redis_instance} = RedisInstances.create_redis_instance(@valid_attrs)

      assert %Ecto.Changeset{} = RedisInstances.change_redis_instance(redis_instance)
    end
  end

  describe "docker naming" do
    test "slugify_name/1 creates Docker-safe slugs" do
      assert RedisInstance.slugify_name("Primary_Queue") == "primary-queue"
      assert RedisInstance.slugify_name("---") == "redis"
    end

    test "docker_container_name_for/1 prefixes the slug" do
      assert RedisInstance.docker_container_name_for("Primary_Queue") ==
               "fuse-redis-primary-queue"

      assert RedisInstance.docker_container_name_for(%RedisInstance{name: "workers"}) ==
               "fuse-redis-workers"
    end
  end
end
