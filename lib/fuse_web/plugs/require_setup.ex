defmodule FuseWeb.Plugs.RequireSetup do
  @moduledoc """
  Redirects browser requests to `/setup` until the console admin password is
  set. This is what closes the "open access" hole: a freshly deployed console
  with no credential funnels every visitor into first-run setup instead of
  serving the app.

  No-op when enforcement is off (test, or `CONSOLE_AUTH_ENFORCE=false`) or once
  setup is complete. The `/setup` path itself is always allowed through so the
  setup form can render and submit. Health probes live on a separate pipeline
  and are never gated.
  """
  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  alias FuseWeb.Auth

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    cond do
      not Auth.enforce?() -> conn
      Auth.configured?() -> conn
      conn.request_path == "/setup" -> conn
      true -> conn |> redirect(to: "/setup") |> halt()
    end
  end
end
