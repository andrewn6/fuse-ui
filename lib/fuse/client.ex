defmodule Fuse.Client do
  @moduledoc """
  The boundary to the fuse orchestrator's REST API.

  This module is both:

    * a **behaviour** declaring one callback per fuse operation, and
    * a thin **dispatcher** that forwards to the configured implementation,
      so contexts can call `Fuse.Client.create_environment/1` without caring
      whether they're hitting HTTP (`Fuse.Client.HTTP`) or the in-memory test
      double (`Fuse.Client.Fake`).

  Swap the implementation with:

      config :fuse, :fuse_client, Fuse.Client.Fake

  Every callback returns `{:ok, value} | {:error, Fuse.Error.t()}`. Endpoints
  with no response body (HTTP 204) return `{:ok, nil}`; list endpoints unwrap
  fuse's `{"environments": [...]}`-style envelope and return `{:ok, list}`.
  Decoding the raw maps into typed structs is the job of the context layer.
  """

  alias Fuse.Error

  @type id :: String.t()
  @type params :: map()
  @type filters :: map()
  @type result(t) :: {:ok, t} | {:error, Error.t()}

  # --- Environments ---
  @callback list_environments(filters()) :: result([map()])
  @callback get_environment(id()) :: result(map())
  @callback create_environment(params()) :: result(map())
  @callback drain_environment(id()) :: result(map() | nil)
  @callback rotate_token(id()) :: result(nil)
  @callback destroy_environment(id()) :: result(nil)

  # --- Snapshots ---
  @callback create_snapshot(vm_id :: id(), params()) :: result(map())
  @callback list_snapshots(filters()) :: result([map()])
  @callback get_snapshot(id()) :: result(map())
  @callback restore_snapshot(id()) :: result(nil)
  @callback delete_snapshot(id()) :: result(nil)

  # --- Hosts ---
  @callback register_host(params()) :: result(map())
  @callback list_hosts() :: result([map()])
  @callback get_host(id()) :: result(map())
  @callback cordon_host(id()) :: result(nil)
  @callback uncordon_host(id()) :: result(nil)
  @callback remove_host(id()) :: result(nil)

  # --- Health (unauthenticated probe) ---
  @callback ready() :: result(map())

  @default_impl Fuse.Client.HTTP

  @doc "The configured client implementation module."
  @spec impl() :: module()
  def impl, do: Application.get_env(:fuse, :fuse_client, @default_impl)

  # --- Environments ---
  def list_environments(filters \\ %{}), do: impl().list_environments(filters)
  def get_environment(id), do: impl().get_environment(id)
  def create_environment(params), do: impl().create_environment(params)
  def drain_environment(id), do: impl().drain_environment(id)
  def rotate_token(id), do: impl().rotate_token(id)
  def destroy_environment(id), do: impl().destroy_environment(id)

  # --- Snapshots ---
  def create_snapshot(vm_id, params \\ %{}), do: impl().create_snapshot(vm_id, params)
  def list_snapshots(filters \\ %{}), do: impl().list_snapshots(filters)
  def get_snapshot(id), do: impl().get_snapshot(id)
  def restore_snapshot(id), do: impl().restore_snapshot(id)
  def delete_snapshot(id), do: impl().delete_snapshot(id)

  # --- Hosts ---
  def register_host(params), do: impl().register_host(params)
  def list_hosts, do: impl().list_hosts()
  def get_host(id), do: impl().get_host(id)
  def cordon_host(id), do: impl().cordon_host(id)
  def uncordon_host(id), do: impl().uncordon_host(id)
  def remove_host(id), do: impl().remove_host(id)

  # --- Health ---
  def ready, do: impl().ready()
end
