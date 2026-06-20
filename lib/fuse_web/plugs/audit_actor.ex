defmodule FuseWeb.Plugs.AuditActor do
  @moduledoc """
  Stamp the request process's audit actor as `api:<remote_ip>`, so audit records
  created by contexts during this request attribute to the inbound API caller.

  Inbound auth uses a single shared token (no per-caller identity), so the source
  IP is the most specific "who" available. `Fuse.Audit` reads this stamp as a
  fallback when a record doesn't carry an explicit actor.
  """

  @behaviour Plug

  alias Fuse.Audit

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    Audit.put_actor("api:" <> to_string(:inet.ntoa(conn.remote_ip)))
    conn
  end
end
