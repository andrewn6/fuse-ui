defmodule FuseWeb.AuthHook do
  @moduledoc """
  LiveView `on_mount` hook that gates the console behind first-run setup and a
  session login.

  Unauthenticated mounts are redirected: to `/setup` when no admin password is
  configured yet, otherwise to `/login`. Authentication uses the console admin
  password (see `FuseWeb.SessionController`); the session is checked on every
  LiveView mount. Audit records from console actions are attributed to
  `"console"`.

  When enforcement is off (test, or `CONSOLE_AUTH_ENFORCE=false`) this hook is a
  pass-through. The policy lives in `FuseWeb.Auth`.
  """

  import Phoenix.LiveView, only: [redirect: 2]

  alias FuseWeb.Auth

  def on_mount(:default, _params, session, socket) do
    cond do
      not Auth.enforce?() ->
        Fuse.Audit.put_actor("console")
        {:cont, socket}

      not Auth.configured?() ->
        {:halt, redirect(socket, to: "/setup")}

      Auth.authenticated?(session) ->
        # attribute audit records created by this LiveView's actions to the console
        Fuse.Audit.put_actor("console")
        {:cont, socket}

      true ->
        {:halt, redirect(socket, to: "/login")}
    end
  end
end
