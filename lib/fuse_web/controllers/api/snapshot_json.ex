defmodule FuseWeb.API.SnapshotJSON do
  @moduledoc """
  Renders `Fuse.Snapshots.Snapshot` structs (including nested exports) as the
  API's JSON data envelope.
  """

  alias Fuse.Snapshots.Snapshot
  alias Fuse.Snapshots.Snapshot.Export

  @doc "Render a list of snapshots."
  def index(%{snapshots: snapshots}) do
    %{data: Enum.map(snapshots, &data/1)}
  end

  @doc "Render a single snapshot."
  def show(%{snapshot: snapshot}) do
    %{data: data(snapshot)}
  end

  @doc "Serialize a `Snapshot` struct into a plain JSON-able map."
  def data(%Snapshot{} = snapshot) do
    %{
      id: snapshot.id,
      vm_id: snapshot.vm_id,
      task_id: snapshot.task_id,
      tenant_id: snapshot.tenant_id,
      parent_snapshot_id: snapshot.parent_snapshot_id,
      mode: snapshot.mode,
      state: snapshot.state,
      comment: snapshot.comment,
      size_bytes: snapshot.size_bytes,
      created_at: datetime(snapshot.created_at),
      updated_at: datetime(snapshot.updated_at),
      retention_until: datetime(snapshot.retention_until),
      last_error: snapshot.last_error,
      export_ref: snapshot.export_ref,
      exports: exports(snapshot.exports)
    }
  end

  defp exports(list) when is_list(list), do: Enum.map(list, &export/1)
  defp exports(_other), do: []

  defp export(%Export{} = export) do
    %{
      destination: export.destination,
      status: export.status,
      requested_at: datetime(export.requested_at),
      updated_at: datetime(export.updated_at),
      last_error: export.last_error
    }
  end

  defp datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp datetime(nil), do: nil
end
