defmodule FuseWeb.API.HostController do
  @moduledoc """
  REST passthrough for fuse hosts (worker nodes).

  Calls into `Fuse.Hosts` and renders via `FuseWeb.API.HostJSON`. Errors from
  the context (`{:error, %Fuse.Error{}}`) are handled by
  `FuseWeb.API.FallbackController`.
  """
  use FuseWeb, :controller

  alias Fuse.Hosts

  action_fallback FuseWeb.API.FallbackController

  def index(conn, _params) do
    with {:ok, hosts} <- Hosts.list() do
      render(conn, :index, hosts: hosts)
    end
  end

  def create(conn, _params) do
    with {:ok, host} <- Hosts.register(conn.body_params) do
      conn
      |> put_status(:created)
      |> render(:show, host: host)
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, host} <- Hosts.get(id) do
      render(conn, :show, host: host)
    end
  end

  def update(conn, %{"id" => id, "action" => "cordon"}) do
    with {:ok, _} <- Hosts.cordon(id) do
      send_resp(conn, :no_content, "")
    end
  end

  def update(conn, %{"id" => id, "action" => "uncordon"}) do
    with {:ok, _} <- Hosts.uncordon(id) do
      send_resp(conn, :no_content, "")
    end
  end

  def update(conn, params) do
    action = Map.get(params, "action")

    conn
    |> put_status(:bad_request)
    |> json(%{
      errors: %{
        code: "invalid_argument",
        message: "unknown or missing action: #{action}"
      }
    })
  end

  def destroy(conn, %{"id" => id}) do
    with {:ok, _} <- Hosts.remove(id) do
      send_resp(conn, :no_content, "")
    end
  end
end
