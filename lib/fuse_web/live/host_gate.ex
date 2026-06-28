defmodule FuseWeb.HostGate do
  @moduledoc """
  LiveView `on_mount` hook that keeps the console out of reach until at least
  one host is connected. A control plane with an empty fleet can't do anything,
  so we funnel the operator into onboarding instead of showing empty consoles.

  Runs after `FuseWeb.AuthHook` (so it only sees authenticated mounts) and
  assigns `:has_hosts?` for the sidebar. Behaviour by page:

    * gated pages (environments, hosts, snapshots, activity) redirect to
      `/onboarding` when the fleet is empty
    * ungated pages (`OnboardingLive`, settings) always render; onboarding
      bounces to `/environments` once a host exists

  When fuse is unreachable we can't tell whether hosts exist, so we let the page
  render (it shows its own "couldn't reach fuse" banner) rather than risk a
  redirect loop. No-op when enforcement is off.
  """

  import Phoenix.LiveView, only: [redirect: 2]
  import Phoenix.Component, only: [assign: 3]

  alias FuseWeb.Auth

  # pages reachable before any host is connected
  @ungated [FuseWeb.OnboardingLive, FuseWeb.SettingsLive.Index]

  def on_mount(:default, _params, _session, socket) do
    if not Auth.enforce?() do
      {:cont, assign(socket, :has_hosts?, true)}
    else
      gate(socket)
    end
  end

  defp gate(socket) do
    case host_presence() do
      {:ok, true} ->
        if socket.view == FuseWeb.OnboardingLive do
          {:halt, redirect(socket, to: "/environments")}
        else
          {:cont, assign(socket, :has_hosts?, true)}
        end

      {:ok, false} ->
        if socket.view in @ungated do
          {:cont, assign(socket, :has_hosts?, false)}
        else
          {:halt, redirect(socket, to: "/onboarding")}
        end

      :error ->
        # fuse unreachable: don't gate, let the page show its error banner
        {:cont, assign(socket, :has_hosts?, true)}
    end
  end

  defp host_presence do
    case Fuse.Hosts.list() do
      {:ok, hosts} -> {:ok, hosts != []}
      {:error, _error} -> :error
    end
  end
end
