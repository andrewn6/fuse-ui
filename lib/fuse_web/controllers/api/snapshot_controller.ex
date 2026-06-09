defmodule FuseWeb.API.SnapshotController do
  @moduledoc """
  REST passthrough for fuse snapshots: list, create (nested under an
  environment), show, restore (via `?action=restore`), and delete.
  """
  use FuseWeb, :controller

  alias Fuse.Snapshots

  action_fallback FuseWeb.API.FallbackController

  def index(conn, _params) do
    with {:ok, snapshots} <- Snapshots.list(conn.query_params) do
      render(conn, :index, snapshots: snapshots)
    end
  end

  def create(conn, %{"vm_id" => vm_id}) do
    with {:ok, snapshot} <- Snapshots.create(vm_id, conn.body_params) do
      conn
      |> put_status(:created)
      |> render(:show, snapshot: snapshot)
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, snapshot} <- Snapshots.get(id) do
      render(conn, :show, snapshot: snapshot)
    end
  end

  def update(conn, %{"id" => id, "action" => "restore"}) do
    with {:ok, _} <- Snapshots.restore(id) do
      send_resp(conn, :no_content, "")
    end
  end

  def update(conn, params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      errors: %{
        code: "invalid_argument",
        message: "unknown or missing action: #{params["action"]}"
      }
    })
  end

  def destroy(conn, %{"id" => id}) do
    with {:ok, _} <- Snapshots.delete(id) do
      send_resp(conn, :no_content, "")
    end
  end
end
