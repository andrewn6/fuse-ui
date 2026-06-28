defmodule Fuse.Snapshots do
  @moduledoc """
  Snapshots context: create/list/get/restore/delete of fuse snapshots.

  Calls go through `Fuse.Client`; raw wire maps are decoded into
  `Fuse.Snapshots.Snapshot` structs (including nested `exports`). Client-side
  problems surface as `%Fuse.Error{code: "invalid_argument"}` for a uniform
  error shape.
  """

  alias Fuse.Audit
  alias Fuse.Client
  alias Fuse.Error
  alias Fuse.Mirror
  alias Fuse.Snapshots.Snapshot

  @type result(t) :: {:ok, t} | {:error, Error.t()}

  # Wire keys accepted in the create body (all optional per fuse).
  @create_keys [:comment, :mode, :retention_seconds, :metadata, :export_ref, :export_status]

  @doc """
  Create a snapshot of the given environment (`vm_id`).

  Optional attrs use fuse's wire keys: `:comment`, `:mode`, `:retention_seconds`,
  `:metadata`, `:export_ref`, `:export_status`.
  """
  @spec create(String.t(), map()) :: result(Snapshot.t())
  def create(vm_id, attrs \\ %{}) do
    with {:ok, vm_id} <- validate_vm_id(vm_id),
         {:ok, map} <- Client.create_snapshot(vm_id, build_create_params(attrs)) do
      snap = Snapshot.from_wire(map)
      Mirror.upsert_snapshot(snap)
      audit("create", snap.id, %{"vm_id" => vm_id})
      {:ok, snap}
    end
  end

  @doc """
  List snapshots, optionally filtered by `:vm_id`, `:task_id`, `:tenant_id`,
  `:state`.
  """
  @spec list(map()) :: result([Snapshot.t()])
  def list(filters \\ %{}) do
    with {:ok, items} <- Client.list_snapshots(filters) do
      snaps = Enum.map(items, &Snapshot.from_wire/1)
      Mirror.upsert_snapshots(snaps)
      {:ok, snaps}
    end
  end

  @doc "Fetch a single snapshot by id."
  @spec get(String.t()) :: result(Snapshot.t())
  def get(id) do
    with {:ok, map} <- Client.get_snapshot(id) do
      snap = Snapshot.from_wire(map)
      Mirror.upsert_snapshot(snap)
      {:ok, snap}
    end
  end

  @doc "Restore a snapshot."
  @spec restore(String.t()) :: result(nil)
  def restore(id) do
    with {:ok, result} <- Client.restore_snapshot(id) do
      audit("restore", id)
      {:ok, result}
    end
  end

  @doc "Delete a snapshot."
  @spec delete(String.t()) :: result(nil)
  def delete(id) do
    with {:ok, result} <- Client.delete_snapshot(id) do
      audit("delete", id)
      {:ok, result}
    end
  end

  # --- internals ---

  defp audit(action, resource_id, metadata \\ %{}) do
    Audit.record(%{
      action: action,
      resource_type: "snapshot",
      resource_id: resource_id,
      metadata: metadata
    })
  end

  defp build_create_params(attrs) do
    for key <- @create_keys,
        value = fetch(attrs, key),
        not is_nil(value),
        into: %{},
        do: {Atom.to_string(key), value}
  end

  defp validate_vm_id(vm_id) when is_binary(vm_id) and vm_id != "", do: {:ok, vm_id}
  defp validate_vm_id(_other), do: {:error, invalid_argument("vm_id is required")}

  defp invalid_argument(message) do
    %Error{code: "invalid_argument", message: message, details: nil, status: nil}
  end

  defp fetch(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
