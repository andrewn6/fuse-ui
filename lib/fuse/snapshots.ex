defmodule Fuse.Snapshots do
  @moduledoc """
  Snapshots context: create/list/get/restore/delete of fuse snapshots.

  Calls go through `Fuse.Client`; raw wire maps are decoded into
  `Fuse.Snapshots.Snapshot` structs (including nested `exports`). Client-side
  problems surface as `%Fuse.Error{code: "invalid_argument"}` for a uniform
  error shape.
  """

  alias Fuse.Client
  alias Fuse.Error
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
      {:ok, Snapshot.from_wire(map)}
    end
  end

  @doc """
  List snapshots, optionally filtered by `:vm_id`, `:task_id`, `:tenant_id`,
  `:state`.
  """
  @spec list(map()) :: result([Snapshot.t()])
  def list(filters \\ %{}) do
    with {:ok, items} <- Client.list_snapshots(filters) do
      {:ok, Enum.map(items, &Snapshot.from_wire/1)}
    end
  end

  @doc "Fetch a single snapshot by id."
  @spec get(String.t()) :: result(Snapshot.t())
  def get(id) do
    with {:ok, map} <- Client.get_snapshot(id) do
      {:ok, Snapshot.from_wire(map)}
    end
  end

  @doc "Restore a snapshot."
  @spec restore(String.t()) :: result(nil)
  def restore(id), do: Client.restore_snapshot(id)

  @doc "Delete a snapshot."
  @spec delete(String.t()) :: result(nil)
  def delete(id), do: Client.delete_snapshot(id)

  # --- internals ---

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
