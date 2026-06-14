defmodule FuseWeb.SettingsLive.Index do
  @moduledoc """
  Settings console: read-only connection info for the configured fuse
  control-plane endpoint. Shows the fuse `base_url`, whether an inbound
  console token is configured (presence only — never the value), and the
  console app version. No secrets are rendered.
  """
  use FuseWeb, :live_view

  alias Fuse.Environments
  alias Fuse.Hosts
  alias Fuse.Snapshots
  alias FuseWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:base_url, base_url())
     |> assign(:token_configured?, token_configured?())
     |> assign(:version, version())
     |> assign(:counts, sidebar_counts())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.console current={:settings} counts={@counts} connection={@connection} flash={@flash}>
      <div class="mx-auto w-full max-w-5xl px-8 py-7">
        <div>
          <h1 class="text-[22px] font-semibold tracking-tight">Settings</h1>
          <p class="mt-1 text-[13px] text-muted">
            Control-plane connection for this console
          </p>
        </div>

        <div class="mt-5 overflow-hidden rounded-xl border border-rail bg-surface">
          <div class="border-b border-rail bg-surface-soft px-5 py-3">
            <h2 class="text-[11px] font-semibold uppercase tracking-wider text-muted">Connection</h2>
          </div>
          <dl class="divide-y divide-rail">
            <.setting_row label="Status" hint="Live reachability of the fuse control plane.">
              <Layouts.badge label={status_label(@connection)} color={status_color(@connection)} />
            </.setting_row>

            <.setting_row
              label="fuse endpoint"
              hint="The control-plane base URL this console talks to."
            >
              <span class="font-mono text-[13px] text-ink">{@base_url}</span>
            </.setting_row>

            <.setting_row
              label="Inbound token"
              hint="Console API auth. Presence only — the value is never shown."
            >
              <Layouts.badge :if={@token_configured?} label="Configured" color={:ok} />
              <Layouts.badge :if={!@token_configured?} label="Not set" color={:muted} />
            </.setting_row>

            <.setting_row label="Console version" hint="The running build of this dashboard.">
              <span class="font-mono text-[13px] text-ink">v{@version}</span>
            </.setting_row>
          </dl>
        </div>
      </div>
    </Layouts.console>
    """
  end

  # --- components ---

  attr :label, :string, required: true
  attr :hint, :string, default: nil
  slot :inner_block, required: true

  defp setting_row(assigns) do
    ~H"""
    <div class="flex items-start justify-between gap-6 px-5 py-4">
      <dt class="min-w-0">
        <span class="block text-[13px] font-medium text-ink">{@label}</span>
        <span :if={@hint} class="mt-0.5 block text-[12px] text-muted">{@hint}</span>
      </dt>
      <dd class="shrink-0 text-right">{render_slot(@inner_block)}</dd>
    </div>
    """
  end

  # --- data ---

  defp base_url do
    case (Application.get_env(:fuse, Fuse.Client.HTTP) || [])[:base_url] do
      url when is_binary(url) and url != "" -> url
      _ -> "—"
    end
  end

  defp token_configured? do
    case (Application.get_env(:fuse, FuseWeb.Plugs.ApiAuth) || [])[:token] do
      token when is_binary(token) and token != "" -> true
      _ -> false
    end
  end

  defp version do
    to_string(Application.spec(:fuse, :vsn) || "dev")
  end

  defp status_label(:ok), do: "Connected"
  defp status_label(:degraded), do: "Degraded"
  defp status_label(:unreachable), do: "Unreachable"
  defp status_label(_), do: "Checking…"

  defp status_color(:ok), do: :ok
  defp status_color(:degraded), do: :warn
  defp status_color(:unreachable), do: :bad
  defp status_color(_), do: :muted

  defp sidebar_counts do
    %{
      environments: safe_count(fn -> Environments.list() end),
      hosts: safe_count(&Hosts.list/0),
      snapshots: safe_count(fn -> Snapshots.list() end)
    }
  end

  defp safe_count(fun) do
    case fun.() do
      {:ok, list} -> length(list)
      _ -> nil
    end
  end
end
