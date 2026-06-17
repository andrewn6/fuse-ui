defmodule FuseWeb.HostLive.Index do
  @moduledoc """
  Hosts console: the fleet of fuse worker nodes, with per-row state, capacity
  (allocated/total), last-seen, and lifecycle actions (cordon / uncordon /
  remove). Reads through `Fuse.Hosts`; degrades to an error banner if fuse is
  unreachable, and shows a host-onboarding card when the fleet is empty.
  """
  use FuseWeb, :live_view

  alias Fuse.Environments
  alias Fuse.Hosts
  alias Fuse.Hosts.Host
  alias Fuse.Snapshots
  alias FuseWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {hosts, load_error} = load_hosts()

    {:ok,
     socket
     |> assign(:page_title, "Hosts")
     |> assign(:load_error, load_error)
     |> assign(:hosts, hosts)
     |> assign(:preset, "medium")
     |> assign(:host, preset_values("medium"))
     |> assign(:counts, sidebar_counts(hosts))}
  end

  @impl true
  def handle_event("cordon", %{"id" => id}, socket) do
    {:noreply, run_action(socket, fn -> Hosts.cordon(id) end, "Host cordoned.")}
  end

  def handle_event("uncordon", %{"id" => id}, socket) do
    {:noreply, run_action(socket, fn -> Hosts.uncordon(id) end, "Host uncordoned.")}
  end

  def handle_event("remove_host", %{"id" => id}, socket) do
    {:noreply, run_action(socket, fn -> Hosts.remove(id) end, "Host removed.")}
  end

  # keep the form controlled so preset clicks / register errors don't wipe input
  def handle_event("validate", %{"host" => params}, socket) do
    {:noreply, assign(socket, :host, params)}
  end

  def handle_event("preset", %{"size" => size}, socket) do
    {:noreply,
     socket
     |> assign(:preset, size)
     |> assign(:host, Map.merge(socket.assigns.host, preset_values(size)))}
  end

  def handle_event("register_host", %{"host" => params}, socket) do
    case Hosts.register(register_attrs(params)) do
      {:ok, _host} ->
        {:noreply,
         socket
         |> reload_hosts()
         |> assign(:preset, "medium")
         |> assign(:host, preset_values("medium"))
         |> put_flash(:info, "Host registered.")}

      {:error, %Fuse.Error{} = error} ->
        {:noreply, put_flash(socket, :error, error.message)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.console current={:hosts} counts={@counts} connection={@connection} flash={@flash}>
      <div class="mx-auto w-full max-w-5xl px-8 py-7">
        <div class="flex items-start justify-between gap-4">
          <div>
            <h1 class="text-[22px] font-semibold tracking-tight">Hosts</h1>
            <p class="mt-1 text-[13px] text-muted">
              Worker nodes in the fleet <span class="text-rail-strong">·</span> {length(@hosts)} total
            </p>
          </div>
          <button
            phx-click={Layouts.show_modal("register-host")}
            class="inline-flex shrink-0 items-center gap-1.5 rounded-lg bg-brand px-3.5 py-2 text-[13px] font-medium text-white shadow-sm transition hover:bg-brand-strong"
          >
            <.icon name="hero-plus" class="size-4" /> Register host
          </button>
        </div>

        <div
          :if={@load_error}
          class="mt-5 flex items-start gap-2.5 rounded-lg border border-bad/30 bg-bad-soft px-4 py-3 text-[13px]"
        >
          <.icon name="hero-exclamation-triangle" class="mt-0.5 size-4 shrink-0 text-bad" />
          <div>
            <p class="font-medium text-bad">Couldn't reach fuse</p>
            <p class="text-muted">{@load_error.message}</p>
          </div>
        </div>

        <div
          :if={@hosts == [] and is_nil(@load_error)}
          class="mt-5 flex flex-col items-center justify-center rounded-xl border border-dashed border-rail bg-surface px-8 py-16 text-center"
        >
          <div class="flex size-12 items-center justify-center rounded-xl bg-brand-soft text-brand">
            <.icon name="hero-server-stack" class="size-6" />
          </div>
          <h2 class="mt-4 text-[15px] font-semibold text-ink">Add your first host</h2>
          <p class="mt-1 max-w-sm text-[13px] text-muted">
            Register a worker node so fuse can schedule environments onto your fleet.
          </p>
          <button
            phx-click={Layouts.show_modal("register-host")}
            class="mt-5 inline-flex items-center gap-1.5 rounded-lg bg-brand px-3.5 py-2 text-[13px] font-medium text-white shadow-sm transition hover:bg-brand-strong"
          >
            <.icon name="hero-plus" class="size-4" /> Register host
          </button>
        </div>

        <div
          :if={@hosts != []}
          class="mt-5 overflow-hidden rounded-xl border border-rail bg-surface"
        >
          <table class="w-full border-collapse text-left">
            <thead>
              <tr class="border-b border-rail bg-surface-soft text-[11px] font-semibold uppercase tracking-wider text-muted">
                <th class="px-5 py-3 font-semibold">Host</th>
                <th class="px-5 py-3 font-semibold">State</th>
                <th class="px-5 py-3 font-semibold">Capacity</th>
                <th class="px-5 py-3 font-semibold">Last seen</th>
                <th class="px-5 py-3 font-semibold"></th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={host <- @hosts}
                id={"host-#{host.id}"}
                class="border-b border-rail transition last:border-0 hover:bg-surface-soft/60"
              >
                <td class="px-5 py-3.5">
                  <div class="font-mono text-[13px] font-medium text-ink">{host.id}</div>
                  <div class="mt-0.5 font-mono text-[11px] text-muted">
                    {region_label(host.region)}
                  </div>
                </td>
                <td class="px-5 py-3.5">
                  <Layouts.badge label={state_label(host)} color={state_color(host)} />
                </td>
                <td class="px-5 py-3.5 font-mono text-[12px] text-muted">
                  {capacity_label(host.allocated, host.capacity)}
                </td>
                <td class="px-5 py-3.5 text-[12px] text-muted">{format_dt(host.last_seen)}</td>
                <td class="px-5 py-3.5">
                  <div class="flex items-center justify-end gap-1.5">
                    <button
                      :if={Host.active?(host)}
                      phx-click="cordon"
                      phx-value-id={host.id}
                      class="rounded-md border border-rail bg-surface px-2.5 py-1 text-[12px] font-medium text-ink/80 transition hover:bg-surface-soft"
                    >
                      Cordon
                    </button>
                    <button
                      :if={Host.cordoned?(host)}
                      phx-click="uncordon"
                      phx-value-id={host.id}
                      class="rounded-md border border-rail bg-surface px-2.5 py-1 text-[12px] font-medium text-ink/80 transition hover:bg-surface-soft"
                    >
                      Uncordon
                    </button>
                    <button
                      phx-click={Layouts.show_modal("confirm-remove-#{host.id}")}
                      class="rounded-md border border-rail bg-surface px-2.5 py-1 text-[12px] font-medium text-bad transition hover:bg-bad-soft"
                    >
                      Remove
                    </button>
                  </div>

                  <Layouts.modal id={"confirm-remove-#{host.id}"}>
                    <:title>Remove host</:title>
                    <p class="text-[13px] text-muted">
                      Remove <span class="font-mono text-ink">{host.id}</span>
                      from the cluster? Existing VMs are not migrated. This can't be undone.
                    </p>
                    <:actions>
                      <button
                        type="button"
                        phx-click={Layouts.hide_modal("confirm-remove-#{host.id}")}
                        class="rounded-lg border border-rail bg-surface px-3 py-1.5 text-[13px] font-medium text-ink/80 transition hover:bg-surface-soft"
                      >
                        Cancel
                      </button>
                      <button
                        type="button"
                        phx-click={
                          Layouts.hide_modal("confirm-remove-#{host.id}")
                          |> JS.push("remove_host", value: %{id: host.id})
                        }
                        class="rounded-lg bg-bad px-3 py-1.5 text-[13px] font-medium text-white transition hover:bg-bad/90"
                      >
                        Remove host
                      </button>
                    </:actions>
                  </Layouts.modal>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <Layouts.modal id="register-host">
        <:title>Register host</:title>
        <form phx-submit="register_host" phx-change="validate" class="space-y-4">
          <div class="grid grid-cols-2 gap-3">
            <.field
              name="id"
              label="Host ID"
              placeholder="host_us_east_1a"
              value={@host["id"]}
              hint="A unique name for this node."
              required
              mono
            />
            <.field
              name="region"
              label="Region"
              placeholder="us-east-1"
              value={@host["region"]}
              hint="Optional. Where this host runs."
            />
          </div>
          <.field
            name="url"
            label="URL"
            placeholder="https://host.internal:8443"
            value={@host["url"]}
            hint="How fuse reaches this host's agent."
            required
            mono
          />

          <div>
            <div class="mb-1.5 flex items-center justify-between gap-2">
              <p class="text-[11px] font-semibold uppercase tracking-wider text-muted">Capacity</p>
              <div class="flex items-center gap-1">
                <.preset_button size="small" label="Small" active={@preset == "small"} />
                <.preset_button size="medium" label="Medium" active={@preset == "medium"} />
                <.preset_button size="large" label="Large" active={@preset == "large"} />
              </div>
            </div>
            <p class="mb-2 text-[11px] text-muted">
              This host's resource budget — pick a node preset or enter exact values for the machine.
            </p>
            <div class="grid grid-cols-2 gap-3">
              <.field
                name="cpus"
                label="vCPUs"
                type="number"
                placeholder="32"
                value={@host["cpus"]}
                hint="Total vCPUs to offer fuse."
                required
              />
              <.field
                name="ram_mb"
                label="RAM (MB)"
                type="number"
                placeholder="65536"
                value={@host["ram_mb"]}
                hint="Total memory to offer, in MB."
                required
              />
              <.field
                name="storage_gb"
                label="Storage (GB)"
                type="number"
                placeholder="1000"
                value={@host["storage_gb"]}
                hint="Disk to offer, in GB."
                required
              />
              <.field
                name="vm_count"
                label="Max VMs"
                type="number"
                placeholder="48"
                value={@host["vm_count"]}
                hint="Hard cap on concurrent microVMs."
                required
              />
            </div>
          </div>

          <div class="flex items-center justify-end gap-2 border-t border-rail pt-3.5">
            <button
              type="button"
              phx-click={Layouts.hide_modal("register-host")}
              class="rounded-lg border border-rail bg-surface px-3 py-1.5 text-[13px] font-medium text-ink/80 transition hover:bg-surface-soft"
            >
              Cancel
            </button>
            <button
              type="submit"
              class="rounded-lg bg-brand px-3.5 py-1.5 text-[13px] font-medium text-white transition hover:bg-brand-strong"
            >
              Register host
            </button>
          </div>
        </form>
      </Layouts.modal>
    </Layouts.console>
    """
  end

  # --- components ---

  attr :size, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false

  defp preset_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="preset"
      phx-value-size={@size}
      class={[
        "rounded-md px-2 py-0.5 text-[11px] font-medium ring-1 transition",
        (@active && "bg-brand-soft text-brand-strong ring-brand/40") ||
          "bg-surface text-muted ring-rail hover:bg-surface-soft"
      ]}
    >
      {@label}
    </button>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :type, :string, default: "text"
  attr :placeholder, :string, default: nil
  attr :value, :any, default: nil
  attr :hint, :string, default: nil
  attr :required, :boolean, default: false
  attr :mono, :boolean, default: false

  defp field(assigns) do
    ~H"""
    <label class="block">
      <span class="mb-1 block text-[12px] font-medium text-ink/80">{@label}</span>
      <input
        type={@type}
        name={"host[#{@name}]"}
        placeholder={@placeholder}
        value={@value}
        required={@required}
        class={[
          "w-full rounded-lg border border-rail bg-surface px-3 py-2 text-[13px] text-ink placeholder:text-muted/60 focus:border-brand focus:outline-none focus:ring-2 focus:ring-brand-soft",
          @mono && "font-mono"
        ]}
      />
      <span :if={@hint} class="mt-1 block text-[11px] text-muted">{@hint}</span>
    </label>
    """
  end

  # --- actions ---

  defp run_action(socket, fun, success_message) do
    case fun.() do
      {:ok, _} ->
        socket
        |> reload_hosts()
        |> put_flash(:info, success_message)

      {:error, %Fuse.Error{} = error} ->
        put_flash(socket, :error, error.message)
    end
  end

  defp reload_hosts(socket) do
    {hosts, load_error} = load_hosts()

    socket
    |> assign(:hosts, hosts)
    |> assign(:load_error, load_error)
    |> assign(:counts, sidebar_counts(hosts))
  end

  defp register_attrs(params) do
    %{
      "id" => blank_to_nil(params["id"]),
      "url" => blank_to_nil(params["url"]),
      "region" => blank_to_nil(params["region"]),
      "capacity" => %{
        "cpus" => to_int(params["cpus"]),
        "ram_mb" => to_int(params["ram_mb"]),
        "storage_gb" => to_int(params["storage_gb"]),
        "vm_count" => to_int(params["vm_count"])
      }
    }
  end

  # capacity defaults for the node-size presets (string-valued so they drop
  # straight into the controlled form's @host params and number inputs)
  defp preset_values("small"),
    do: %{"cpus" => "8", "ram_mb" => "16384", "storage_gb" => "200", "vm_count" => "8"}

  defp preset_values("large"),
    do: %{"cpus" => "64", "ram_mb" => "131072", "storage_gb" => "2000", "vm_count" => "96"}

  defp preset_values(_medium),
    do: %{"cpus" => "32", "ram_mb" => "65536", "storage_gb" => "1000", "vm_count" => "48"}

  # --- data ---

  defp load_hosts do
    case Hosts.list() do
      {:ok, hosts} -> {hosts, nil}
      {:error, error} -> {[], error}
    end
  end

  defp sidebar_counts(hosts) do
    %{
      environments: safe_count(fn -> Environments.list() end),
      hosts: length(hosts),
      snapshots: safe_count(fn -> Snapshots.list() end)
    }
  end

  defp safe_count(fun) do
    case fun.() do
      {:ok, list} -> length(list)
      _ -> nil
    end
  end

  # --- formatting ---

  defp state_label(host) do
    cond do
      Host.active?(host) -> "Active"
      Host.cordoned?(host) -> "Cordoned"
      Host.draining?(host) -> "Draining"
      true -> label_for(host.state)
    end
  end

  defp state_color(host) do
    cond do
      Host.active?(host) -> :ok
      Host.cordoned?(host) -> :warn
      Host.draining?(host) -> :warn
      true -> :muted
    end
  end

  defp label_for(nil), do: "Unknown"
  defp label_for(state), do: String.capitalize(state)

  defp region_label(nil), do: "—"
  defp region_label(""), do: "—"
  defp region_label(region), do: region

  # "alloc/total vCPU · alloc/total GB · alloc/total VMs", nil-safe per field.
  defp capacity_label(allocated, capacity) do
    [
      "#{used_total(cap_field(allocated, :cpus), cap_field(capacity, :cpus))} vCPU",
      "#{used_total(ram_gb(cap_field(allocated, :ram_mb)), ram_gb(cap_field(capacity, :ram_mb)))} GB",
      "#{used_total(cap_field(allocated, :vm_count), cap_field(capacity, :vm_count))} VMs"
    ]
    |> Enum.join(" · ")
  end

  defp cap_field(nil, _key), do: nil
  defp cap_field(%Host.Capacity{} = cap, key), do: Map.get(cap, key)

  defp used_total(used, total), do: "#{num(used)}/#{num(total)}"

  defp num(nil), do: "—"
  defp num(value), do: to_string(value)

  defp ram_gb(nil), do: nil
  defp ram_gb(ram_mb), do: trim_float(Float.round(ram_mb / 1024, 1))

  defp trim_float(float) do
    if float == trunc(float), do: trunc(float), else: float
  end

  defp format_dt(nil), do: "—"
  defp format_dt(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  # --- helpers ---

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(value) when is_binary(value), do: value |> String.trim() |> nilify_empty()

  defp nilify_empty(""), do: nil
  defp nilify_empty(value), do: value

  defp to_int(nil), do: nil

  defp to_int(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, _rest} -> int
      :error -> nil
    end
  end

  defp to_int(value) when is_integer(value), do: value
end
