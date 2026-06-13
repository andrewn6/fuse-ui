defmodule FuseWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use FuseWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href="/" class="flex-1 flex w-fit items-center gap-2">
          <img src={~p"/images/logo.svg"} width="36" />
          <span class="text-sm font-semibold">v{Application.spec(:phoenix, :vsn)}</span>
        </a>
      </div>
      <div class="flex-none">
        <ul class="flex flex-column px-1 space-x-4 items-center">
          <li>
            <a href="https://phoenixframework.org/" class="btn btn-ghost">Website</a>
          </li>
          <li>
            <a href="https://github.com/phoenixframework/phoenix" class="btn btn-ghost">GitHub</a>
          </li>
          <li>
            <.theme_toggle />
          </li>
          <li>
            <a href="https://hexdocs.pm/phoenix/overview.html" class="btn btn-primary">
              Get Started <span aria-hidden="true">&rarr;</span>
            </a>
          </li>
        </ul>
      </div>
    </header>

    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end

  @doc """
  The Fuse Console application shell: a fixed sidebar (brand, workspace, search,
  navigation) plus a scrollable main content slot. Matches the "Fuse — Console"
  design.

  `current` highlights the active nav item; `counts` is a map like
  `%{environments: 7, hosts: 4, snapshots: 6}` for the sidebar badges.
  """
  attr :current, :atom,
    default: nil,
    doc: ":environments | :hosts | :snapshots | :activity | :settings"

  attr :counts, :map, default: %{}
  attr :flash, :map, default: %{}
  slot :inner_block, required: true

  def console(assigns) do
    assigns =
      assign_new(assigns, :version, fn ->
        "v" <> to_string(Application.spec(:fuse, :vsn) || "dev")
      end)

    ~H"""
    <div class="flex h-screen overflow-hidden bg-canvas text-ink">
      <aside class="flex w-[260px] shrink-0 flex-col border-r border-rail bg-surface">
        <div class="flex items-center justify-between px-4 pt-4 pb-3">
          <div class="flex items-center gap-2.5">
            <div class="flex size-8 items-center justify-center rounded-lg bg-brand text-white shadow-sm">
              <.icon name="hero-bolt-solid" class="size-[18px]" />
            </div>
            <span class="text-[15px] font-semibold tracking-tight">Fuse</span>
          </div>
          <span class="rounded-md bg-surface-soft px-1.5 py-0.5 text-[11px] font-medium text-muted ring-1 ring-rail">
            {@version}
          </span>
        </div>

        <div class="px-3">
          <button class="flex w-full items-center gap-2.5 rounded-lg border border-rail bg-surface px-2.5 py-2 text-left hover:bg-surface-soft">
            <span class="flex size-6 items-center justify-center rounded-md bg-ink text-[11px] font-semibold text-canvas">
              f
            </span>
            <span class="flex-1 leading-tight">
              <span class="block text-[13px] font-medium">flint</span>
              <span class="block text-[11px] text-muted">prod · us-east-1</span>
            </span>
            <.icon name="hero-chevron-up-down" class="size-4 text-muted" />
          </button>
        </div>

        <div class="px-3 pt-3">
          <button class="flex w-full items-center gap-2 rounded-lg border border-rail bg-surface-soft px-2.5 py-2 text-[13px] text-muted hover:bg-canvas">
            <.icon name="hero-magnifying-glass" class="size-4" />
            <span class="flex-1 text-left">Search &amp; run…</span>
            <kbd class="rounded border border-rail bg-surface px-1 text-[10px] font-medium">⌘K</kbd>
          </button>
        </div>

        <nav class="flex-1 overflow-y-auto px-3 py-4">
          <p class="px-2.5 pb-1.5 text-[10px] font-semibold uppercase tracking-wider text-muted">
            Infrastructure
          </p>
          <div class="space-y-0.5">
            <.nav_item
              icon="hero-squares-2x2"
              label="Environments"
              navigate={~p"/environments"}
              active={@current == :environments}
              count={@counts[:environments]}
            />
            <.nav_item
              icon="hero-server-stack"
              label="Hosts"
              navigate={~p"/hosts"}
              active={@current == :hosts}
              count={@counts[:hosts]}
            />
            <.nav_item
              icon="hero-square-3-stack-3d"
              label="Snapshots"
              navigate={~p"/snapshots"}
              active={@current == :snapshots}
              count={@counts[:snapshots]}
            />
          </div>

          <p class="px-2.5 pt-5 pb-1.5 text-[10px] font-semibold uppercase tracking-wider text-muted">
            Observability
          </p>
          <div class="space-y-0.5">
            <.nav_item
              icon="hero-signal"
              label="Activity"
              navigate={~p"/activity"}
              active={@current == :activity}
            />
            <.nav_item
              icon="hero-cog-6-tooth"
              label="Settings"
              navigate={~p"/settings"}
              active={@current == :settings}
            />
          </div>
        </nav>

        <div class="flex items-center gap-2.5 border-t border-rail px-4 py-3">
          <span class="flex size-7 items-center justify-center rounded-full bg-surface-soft text-[11px] font-semibold text-muted ring-1 ring-rail">
            U
          </span>
          <span class="flex-1 truncate font-mono text-[11px] text-muted">usr_10vd…7hsi</span>
          <%!-- theme toggle: moon switches to dark (shown in light mode), sun switches
                back (shown in dark mode); state lives in localStorage via root.html.heex --%>
          <button
            type="button"
            phx-click={JS.dispatch("phx:set-theme")}
            data-phx-theme="dark"
            class="flex rounded-md p-1 text-muted hover:bg-surface-soft hover:text-ink dark:hidden"
            title="Switch to dark theme"
            aria-label="Switch to dark theme"
          >
            <.icon name="hero-moon-micro" class="size-4" />
          </button>
          <button
            type="button"
            phx-click={JS.dispatch("phx:set-theme")}
            data-phx-theme="light"
            class="hidden rounded-md p-1 text-muted hover:bg-surface-soft hover:text-ink dark:flex"
            title="Switch to light theme"
            aria-label="Switch to light theme"
          >
            <.icon name="hero-sun-micro" class="size-4" />
          </button>
          <.link
            href={~p"/logout"}
            method="delete"
            class="rounded-md p-1 text-muted hover:bg-surface-soft hover:text-ink"
            title="Sign out"
          >
            <.icon name="hero-arrow-right-start-on-rectangle" class="size-4" />
          </.link>
        </div>
      </aside>

      <main class="flex min-w-0 flex-1 flex-col overflow-y-auto">
        {render_slot(@inner_block)}
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc "A single sidebar navigation item. Inert (muted) when `navigate` is nil."
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :navigate, :string, default: nil
  attr :active, :boolean, default: false
  attr :count, :any, default: nil

  def nav_item(%{navigate: nil} = assigns) do
    ~H"""
    <div
      class="flex cursor-default items-center gap-2.5 rounded-lg px-2.5 py-1.5 text-[13px] font-medium text-muted/60"
      title="Coming soon"
    >
      <.icon name={@icon} class="size-[18px] text-muted/40" />
      <span class="flex-1">{@label}</span>
      <span
        :if={@count}
        class="rounded-md bg-surface-soft px-1.5 py-0.5 text-[11px] tabular-nums text-muted"
      >
        {@count}
      </span>
    </div>
    """
  end

  def nav_item(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class={[
        "group flex items-center gap-2.5 rounded-lg px-2.5 py-1.5 text-[13px] font-medium",
        @active && "bg-brand-soft text-brand-strong",
        !@active && "text-ink/80 hover:bg-surface-soft"
      ]}
    >
      <.icon name={@icon} class={"size-[18px] " <> ((@active && "text-brand") || "text-muted")} />
      <span class="flex-1">{@label}</span>
      <span
        :if={@count}
        class={[
          "rounded-md px-1.5 py-0.5 text-[11px] tabular-nums",
          (@active && "bg-surface text-brand-strong") || "bg-surface-soft text-muted"
        ]}
      >
        {@count}
      </span>
    </.link>
    """
  end

  @doc """
  An accessible, JS-toggled dialog. Hidden by default; open it with
  `show_modal(id)` and close it with `hide_modal(id)` (or the X button /
  backdrop click). Slots: `:title`, `:inner_block` (body), `:actions` (footer).

  ## Example

      <.modal id="confirm-remove">
        <:title>Remove host</:title>
        <p class="text-[13px] text-muted">This can't be undone.</p>
        <:actions>
          <button phx-click={hide_modal("confirm-remove")}>Cancel</button>
          <button phx-click="remove_host" phx-value-id={@id}>Remove</button>
        </:actions>
      </.modal>
  """
  attr :id, :string, required: true

  slot :title
  slot :inner_block, required: true
  slot :actions

  def modal(assigns) do
    ~H"""
    <div id={@id} class="relative z-50 hidden">
      <div
        id={"#{@id}-bg"}
        class="fixed inset-0 bg-ink/40 transition-opacity"
        aria-hidden="true"
      />
      <div
        class="fixed inset-0 flex items-center justify-center overflow-y-auto p-4"
        role="dialog"
        aria-modal="true"
        aria-labelledby={"#{@id}-title"}
      >
        <div
          id={"#{@id}-content"}
          phx-click-away={hide_modal(@id)}
          phx-window-keydown={hide_modal(@id)}
          phx-key="escape"
          class="w-full max-w-md rounded-2xl border border-rail bg-surface shadow-lg"
        >
          <div class="flex items-start justify-between gap-4 px-5 pt-5">
            <h2 :if={@title != []} id={"#{@id}-title"} class="text-[15px] font-semibold text-ink">
              {render_slot(@title)}
            </h2>
            <button
              type="button"
              phx-click={hide_modal(@id)}
              class="-mr-1 -mt-1 rounded-md p-1 text-muted hover:bg-surface-soft hover:text-ink"
              aria-label="Close"
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>

          <div class="px-5 py-4 text-[13px] text-ink">
            {render_slot(@inner_block)}
          </div>

          <div
            :if={@actions != []}
            class="flex items-center justify-end gap-2 border-t border-rail px-5 py-3.5"
          >
            {render_slot(@actions)}
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc "Opens the modal with id `id`: reveals the container, transitions in the panel, and focuses it."
  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      transition: {"transition-opacity ease-out duration-200", "opacity-0", "opacity-100"}
    )
    |> show("##{id}-content")
    |> JS.focus_first(to: "##{id}-content")
  end

  @doc "Closes the modal with id `id`: transitions out the panel/backdrop, hides the container, and restores focus."
  def hide_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      transition: {"transition-opacity ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> hide("##{id}-content")
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.pop_focus()
  end

  @doc """
  A status pill: a colored dot plus a label. Mirrors the Environments
  `state_badge` look. `color` selects the palette (`:ok | :warn | :bad | :muted`).

  ## Example

      <.badge label="Ready" color={:ok} />
  """
  attr :label, :string, required: true
  attr :color, :atom, default: :muted, values: [:ok, :warn, :bad, :muted]

  def badge(assigns) do
    {dot, text, bg} = badge_palette(assigns.color)
    assigns = assign(assigns, dot: dot, text: text, bg: bg)

    ~H"""
    <span class={[
      "inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[12px] font-medium",
      @bg,
      @text
    ]}>
      <span class={["size-1.5 rounded-full", @dot]} />
      {@label}
    </span>
    """
  end

  # {dot, text, background} — keyed by atom; mirrors EnvironmentLive badge_classes/1.
  defp badge_palette(:ok), do: {"bg-ok", "text-ok", "bg-ok-soft"}
  defp badge_palette(:warn), do: {"bg-warn", "text-warn", "bg-warn-soft"}
  defp badge_palette(:bad), do: {"bg-bad", "text-bad", "bg-bad-soft"}
  defp badge_palette(_), do: {"bg-muted", "text-muted", "bg-surface-soft"}
end
