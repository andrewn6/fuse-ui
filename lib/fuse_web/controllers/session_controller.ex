defmodule FuseWeb.SessionController do
  @moduledoc """
  Browser session login for the console. The user submits the control-plane
  token; on a constant-time match we mark the Phoenix session authenticated and
  send them to the dashboard. Logout drops the session.

  Uses the same token as the inbound API (`FuseWeb.Plugs.ApiAuth`); when no token
  is configured the console is open (dev/test) and login is a formality.
  """
  use FuseWeb, :controller

  def new(conn, _params) do
    # Already past the gate (authenticated or insecure mode) -> skip the form.
    if FuseWeb.AuthHook.authenticated?(get_session(conn)) do
      redirect(conn, to: ~p"/environments")
    else
      render(conn, :new, error: nil, page_title: "Sign in")
    end
  end

  def create(conn, %{"token" => token}) do
    if valid_token?(token) do
      conn
      |> renew_session()
      |> put_session(:fuse_authenticated, true)
      |> redirect(to: ~p"/environments")
    else
      conn
      |> put_status(:unauthorized)
      |> render(:new, error: "Invalid token. Check your CONTROL_PLANE_TOKEN.", page_title: "Sign in")
    end
  end

  def delete(conn, _params) do
    conn
    |> renew_session()
    |> redirect(to: ~p"/login")
  end

  @doc "The configured control-plane token (shared with the inbound API plug)."
  def configured_token do
    :fuse
    |> Application.get_env(FuseWeb.Plugs.ApiAuth, [])
    |> Keyword.get(:token)
  end

  defp valid_token?(presented) do
    case configured_token() do
      token when is_binary(token) and token != "" ->
        is_binary(presented) and Plug.Crypto.secure_compare(presented, token)

      _ ->
        # Insecure mode: no token required.
        true
    end
  end

  # Renew the session id to prevent fixation, dropping any prior contents.
  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
