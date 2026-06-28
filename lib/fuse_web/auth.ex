defmodule FuseWeb.Auth do
  @moduledoc """
  Browser-console access policy.

  The console is gated by a single admin password (see `Fuse.Admin`). This
  module is the one place that decides whether the gate is active and what a
  request is allowed to do, so the plug (`FuseWeb.Plugs.RequireSetup`), the
  controllers (`SetupController` / `SessionController`), and the LiveView hooks
  (`AuthHook` / `HostGate`) all agree.

  Gating is on by default (dev/prod) and disabled in test, mirroring how the
  mirror/audit layers are turned off there. Deployments that front the console
  with their own auth can opt out via `CONSOLE_AUTH_ENFORCE=false`.
  """

  alias Fuse.Admin

  @doc "Whether the console requires setup + login. Off only when explicitly disabled."
  @spec enforce?() :: boolean()
  def enforce? do
    Application.get_env(:fuse, __MODULE__, [])[:enforce] != false
  end

  @doc "Whether first-run setup is complete (an admin password exists)."
  @spec configured?() :: boolean()
  def configured?, do: Admin.configured?()

  @doc "Verify a presented console password."
  @spec verify_password(String.t()) :: boolean()
  def verify_password(password), do: Admin.verify_password(password)

  @doc "Whether a Phoenix session is authenticated for the console."
  @spec authenticated?(map()) :: boolean()
  def authenticated?(session) when is_map(session) do
    session["fuse_authenticated"] == true
  end
end
