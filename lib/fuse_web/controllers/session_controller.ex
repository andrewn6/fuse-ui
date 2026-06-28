defmodule FuseWeb.SessionController do
  @moduledoc """
  Browser session login for the console. The operator submits the admin
  password (set during first-run setup, see `FuseWeb.SetupController`); on a
  match we mark the Phoenix session authenticated and send them to the
  dashboard. Logout drops the session.

  The console password is distinct from `CONTROL_PLANE_TOKEN`, which remains the
  bearer token for the inbound `/api/v1` surface.
  """
  use FuseWeb, :controller

  alias FuseWeb.Auth

  def new(conn, _params) do
    cond do
      not Auth.enforce?() -> redirect(conn, to: ~p"/environments")
      not Auth.configured?() -> redirect(conn, to: ~p"/setup")
      Auth.authenticated?(get_session(conn)) -> redirect(conn, to: ~p"/environments")
      true -> render(conn, :new, error: nil, page_title: "Sign in")
    end
  end

  def create(conn, params) do
    password = params["password"] || ""

    if Auth.verify_password(password) do
      conn
      |> renew_session()
      |> put_session(:fuse_authenticated, true)
      |> redirect(to: ~p"/")
    else
      conn
      |> put_status(:unauthorized)
      |> render(:new, error: "Invalid password.", page_title: "Sign in")
    end
  end

  def delete(conn, _params) do
    conn
    |> renew_session()
    |> redirect(to: ~p"/login")
  end

  # Renew the session id to prevent fixation, dropping any prior contents.
  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
