defmodule FuseWeb.AuthHook do
  @moduledoc """
  LiveView `on_mount` hook that gates the console behind a session login.

  Authentication uses the same `CONTROL_PLANE_TOKEN` as the inbound API
  (`FuseWeb.Plugs.ApiAuth`): the user exchanges the token for a Phoenix session
  via `FuseWeb.SessionController`, and this hook checks that session on every
  LiveView mount.

  Mirrors the API plug's "empty token disables auth" behaviour: when no token is
  configured (dev/test), the console is open and this hook is a pass-through.
  """

  import Phoenix.LiveView, only: [redirect: 2]

  def on_mount(:default, _params, session, socket) do
    if authenticated?(session) do
      # attribute audit records created by this LiveView's actions to the console
      Fuse.Audit.put_actor("console")
      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/login")}
    end
  end

  @doc "Whether the session is authenticated, accounting for insecure (no-token) mode."
  def authenticated?(session) do
    case FuseWeb.SessionController.configured_token() do
      token when is_binary(token) and token != "" -> session["fuse_authenticated"] == true
      _ -> true
    end
  end
end
