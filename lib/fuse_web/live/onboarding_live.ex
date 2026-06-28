defmodule FuseWeb.OnboardingLive do
  @moduledoc """
  First-host onboarding: a full-page funnel shown once the operator is signed in
  but the fleet is empty. `FuseWeb.HostGate` only routes here when no host
  exists (and sends them on to the console once one does), so this page's job is
  simply to register the first host. On success it navigates to the dashboard,
  which the gate now lets through.

  Reuses the host-registration form pieces from `FuseWeb.HostRegistration`.
  """
  use FuseWeb, :live_view

  alias Fuse.Hosts
  alias FuseWeb.HostRegistration
  alias FuseWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Connect a host")
     |> assign(:preset, "medium")
     |> assign(:host, HostRegistration.preset_values("medium"))}
  end

  @impl true
  def handle_event("validate", %{"host" => params}, socket) do
    {:noreply, assign(socket, :host, params)}
  end

  def handle_event("preset", %{"size" => size}, socket) do
    {:noreply,
     socket
     |> assign(:preset, size)
     |> assign(:host, Map.merge(socket.assigns.host, HostRegistration.preset_values(size)))}
  end

  def handle_event("register_host", %{"host" => params}, socket) do
    case Hosts.register(HostRegistration.attrs_from_params(params)) do
      {:ok, _host} ->
        {:noreply,
         socket
         |> put_flash(:info, "Host connected.")
         |> push_navigate(to: ~p"/environments")}

      {:error, %Fuse.Error{} = error} ->
        {:noreply, put_flash(socket, :error, error.message)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-canvas text-ink">
      <div class="mx-auto flex max-w-lg flex-col px-4 py-10">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2.5">
            <div class="flex size-8 items-center justify-center rounded-lg bg-brand text-white shadow-sm">
              <.icon name="hero-bolt-solid" class="size-[18px]" />
            </div>
            <span class="text-[15px] font-semibold tracking-tight">Fuse</span>
          </div>
          <.link
            href={~p"/logout"}
            method="delete"
            class="inline-flex items-center gap-1.5 text-[12px] font-medium text-muted hover:text-ink"
          >
            <.icon name="hero-arrow-right-start-on-rectangle" class="size-4" /> Sign out
          </.link>
        </div>

        <div class="mt-8">
          <p class="text-[11px] font-semibold uppercase tracking-wider text-brand">Get started</p>
          <h1 class="mt-1.5 text-[24px] font-semibold tracking-tight">Connect your first host</h1>
          <p class="mt-2 text-[13px] leading-relaxed text-muted">
            A host is a worker node fuse schedules microVM environments onto. Register one and the
            console unlocks. fuse reaches the host's agent at the URL you provide.
          </p>
        </div>

        <div
          :if={@connection == :unreachable}
          class="mt-5 flex items-start gap-2.5 rounded-lg border border-bad/30 bg-bad-soft px-4 py-3 text-[13px]"
        >
          <.icon name="hero-exclamation-triangle" class="mt-0.5 size-4 shrink-0 text-bad" />
          <div>
            <p class="font-medium text-bad">Can't reach fuse</p>
            <p class="text-muted">
              The control plane is unreachable, so registration will fail. Check the connection and try again.
            </p>
          </div>
        </div>

        <div class="mt-6 rounded-2xl border border-rail bg-surface p-6 shadow-sm">
          <form phx-submit="register_host" phx-change="validate" class="space-y-4">
            <div class="grid grid-cols-2 gap-3">
              <HostRegistration.field
                name="id"
                label="Host ID"
                placeholder="host_us_east_1a"
                value={@host["id"]}
                hint="A unique name for this node."
                required
                mono
              />
              <HostRegistration.field
                name="region"
                label="Region"
                placeholder="us-east-1"
                value={@host["region"]}
                hint="Optional. Where this host runs."
              />
            </div>
            <HostRegistration.field
              name="url"
              label="URL"
              placeholder="https://host.internal:8443"
              value={@host["url"]}
              hint="How fuse reaches this host's agent."
              required
              mono
            />

            <HostRegistration.capacity_fields preset={@preset} host={@host} />

            <div class="border-t border-rail pt-4">
              <button
                type="submit"
                class="inline-flex w-full items-center justify-center gap-1.5 rounded-lg bg-brand px-3.5 py-2.5 text-[13px] font-medium text-white shadow-sm transition hover:bg-brand-strong"
              >
                <.icon name="hero-server-stack" class="size-4" /> Connect host
              </button>
            </div>
          </form>
        </div>
      </div>

      <Layouts.flash_group flash={@flash} />
    </div>
    """
  end
end
