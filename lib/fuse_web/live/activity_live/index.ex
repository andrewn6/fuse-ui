defmodule FuseWeb.ActivityLive.Index do
  @moduledoc """
  Activity console: fuse exposes no cluster-wide activity/audit API, so this
  screen is deliberately honest — it renders an info card explaining that a
  cross-cluster feed isn't available yet and that per-environment event
  streams (SSE) will surface here later. It still loads sidebar counts.
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
     |> assign(:page_title, "Activity")
     |> assign(:counts, sidebar_counts())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.console current={:activity} counts={@counts} connection={@connection} flash={@flash}>
      <div class="mx-auto w-full max-w-5xl px-8 py-7">
        <div>
          <h1 class="text-[22px] font-semibold tracking-tight">Activity</h1>
          <p class="mt-1 text-[13px] text-muted">
            Cluster events and per-environment streams
          </p>
        </div>

        <div class="mt-5 rounded-xl border border-rail bg-surface">
          <div class="flex flex-col items-center px-8 py-16 text-center">
            <div class="flex size-11 items-center justify-center rounded-full bg-surface-soft ring-1 ring-rail">
              <.icon name="hero-signal" class="size-5 text-muted" />
            </div>
            <h2 class="mt-4 text-[15px] font-semibold text-ink">No activity feed yet</h2>
            <p class="mt-1.5 max-w-md text-[13px] leading-relaxed text-muted">
              fuse doesn't expose a cluster-wide activity or audit log. When per-environment
              event streams (SSE) land, they'll surface here as a live feed.
            </p>
          </div>
        </div>
      </div>
    </Layouts.console>
    """
  end

  # --- data ---

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
