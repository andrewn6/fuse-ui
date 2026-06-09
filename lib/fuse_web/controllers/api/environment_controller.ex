defmodule FuseWeb.API.EnvironmentController do
  @moduledoc """
  REST passthrough for the `Fuse.Environments` context: list/create/show/
  drain/rotate-token/destroy of fuse microVM environments.
  """
  use FuseWeb, :controller

  alias Fuse.Environments

  action_fallback FuseWeb.API.FallbackController

  def index(conn, _params) do
    with {:ok, environments} <- Environments.list(conn.query_params) do
      render(conn, :index, environments: environments)
    end
  end

  def create(conn, _params) do
    with {:ok, environment} <- Environments.create(conn.body_params) do
      conn
      |> put_status(:created)
      |> render(:show, environment: environment)
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, environment} <- Environments.get(id) do
      render(conn, :show, environment: environment)
    end
  end

  def update(conn, %{"id" => id, "action" => "drain"}) do
    with {:ok, environment} <- Environments.drain(id) do
      render(conn, :show, environment: environment)
    end
  end

  def update(conn, %{"id" => id, "action" => "rotate-token"}) do
    with {:ok, _nil} <- Environments.rotate_token(id) do
      send_resp(conn, :no_content, "")
    end
  end

  def update(conn, params) do
    unknown_action(conn, params["action"])
  end

  def destroy(conn, %{"id" => id}) do
    with {:ok, _nil} <- Environments.destroy(id) do
      send_resp(conn, :no_content, "")
    end
  end

  defp unknown_action(conn, action) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      errors: %{
        code: "invalid_argument",
        message: "unknown or missing action: #{action}"
      }
    })
  end
end
