defmodule Fuse.RedisInstances.RedisInstance do
  use Ecto.Schema
  import Ecto.Changeset

  @docker_container_prefix "fuse-redis-"
  @statuses ~w(created starting running stopped error deleted)

  schema "redis_instances" do
    field :name, :string
    field :docker_container_id, :string
    field :docker_container_name, :string
    field :image, :string, default: "redis:7-alpine"
    field :host, :string, default: "127.0.0.1"
    field :port, :integer
    field :memory_mb, :integer, default: 256
    field :cpu_limit, :float, default: 0.25
    field :status, :string, default: "created"
    field :last_seen_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(redis_instance, attrs) do
    redis_instance
    |> cast(attrs, [
      :name,
      :docker_container_id,
      :docker_container_name,
      :image,
      :host,
      :port,
      :memory_mb,
      :cpu_limit,
      :status,
      :last_seen_at
    ])
    |> validate_required([:name, :image, :host, :memory_mb, :cpu_limit, :status])
    |> validate_length(:name, min: 2, max: 80)
    |> validate_format(:name, ~r/^[a-zA-Z0-9][a-zA-Z0-9_-]*$/)
    |> put_default_docker_container_name()
    |> validate_length(:docker_container_name, max: 255)
    |> validate_format(:docker_container_name, ~r/^[a-zA-Z0-9][a-zA-Z0-9_.-]*$/)
    |> validate_number(:port, greater_than_or_equal_to: 1, less_than_or_equal_to: 65_535)
    |> validate_number(:memory_mb, greater_than_or_equal_to: 128, less_than_or_equal_to: 8_192)
    |> validate_number(:cpu_limit, greater_than_or_equal_to: 0.1, less_than_or_equal_to: 8.0)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:name)
    |> unique_constraint(:docker_container_id)
    |> unique_constraint(:docker_container_name)
  end

  def docker_container_name_for(%__MODULE__{name: name}), do: docker_container_name_for(name)

  def docker_container_name_for(name) when is_binary(name) do
    @docker_container_prefix <> slugify_name(name)
  end

  def slugify_name(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> truncate_slug()
  end

  defp put_default_docker_container_name(changeset) do
    case {get_field(changeset, :docker_container_name), get_field(changeset, :name)} do
      {value, name} when value in [nil, ""] and is_binary(name) ->
        put_change(changeset, :docker_container_name, docker_container_name_for(name))

      _other ->
        changeset
    end
  end

  defp truncate_slug(""), do: "redis"

  defp truncate_slug(slug) do
    slug
    |> String.slice(0, 80)
    |> String.trim("-")
    |> case do
      "" -> "redis"
      truncated -> truncated
    end
  end
end
