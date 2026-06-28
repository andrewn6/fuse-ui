defmodule FuseWeb.HostRegistration do
  @moduledoc """
  Shared pieces of the host-registration form, used by both the hosts console
  (`FuseWeb.HostLive.Index`, in a modal) and first-run onboarding
  (`FuseWeb.OnboardingLive`, full page).

  Provides the field/preset components and the param coercion that turns the
  controlled form's string params into the attrs `Fuse.Hosts.register/1` wants.
  The surrounding `<form>`, action buttons, and `handle_event/3` callbacks
  (`validate` / `preset` / `register_host`) live in each caller, since their
  layout and post-submit behaviour differ.
  """
  use FuseWeb, :html

  @doc "Build the attrs map for `Fuse.Hosts.register/1` from controlled form params."
  def attrs_from_params(params) do
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

  @doc """
  Capacity defaults for the node-size presets. String-valued so they drop
  straight into the controlled form's params and number inputs.
  """
  def preset_values("small"),
    do: %{"cpus" => "8", "ram_mb" => "16384", "storage_gb" => "200", "vm_count" => "8"}

  def preset_values("large"),
    do: %{"cpus" => "64", "ram_mb" => "131072", "storage_gb" => "2000", "vm_count" => "96"}

  def preset_values(_medium),
    do: %{"cpus" => "32", "ram_mb" => "65536", "storage_gb" => "1000", "vm_count" => "48"}

  @doc """
  The capacity preset selector plus the four capacity inputs. Emits `preset`
  events; the caller owns the surrounding form and the `preset` handler.
  """
  attr :preset, :string, required: true
  attr :host, :map, required: true

  def capacity_fields(assigns) do
    ~H"""
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
    """
  end

  attr :size, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false

  def preset_button(assigns) do
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

  def field(assigns) do
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

  # --- coercion helpers ---

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
