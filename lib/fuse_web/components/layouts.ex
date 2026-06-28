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
  The Fuse Console application shell: a fixed sidebar (brand, search, navigation)
  plus a scrollable main content slot. Matches the "Fuse — Console" design.

  `current` highlights the active nav item; `counts` is a map like
  `%{environments: 7, hosts: 4, snapshots: 6}` for the sidebar badges.
  """
  attr :current, :atom,
    default: nil,
    doc: ":environments | :hosts | :snapshots | :activity | :settings"

  attr :counts, :map, default: %{}
  attr :flash, :map, default: %{}

  attr :connection, :atom,
    default: :checking,
    doc: ":checking | :ok | :degraded | :unreachable (from FuseWeb.Connection)"

  attr :has_hosts, :boolean,
    default: true,
    doc: "false locks the nav to onboarding + settings until a host is connected"

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
          <.link
            navigate={~p"/settings"}
            class="flex w-full items-center gap-2.5 rounded-lg border border-rail bg-surface px-2.5 py-2 text-left hover:bg-surface-soft"
            title="Control-plane connection"
          >
            <span class={["size-2 shrink-0 rounded-full", conn_dot(@connection)]} />
            <span class="min-w-0 flex-1 leading-tight">
              <span class="block truncate font-mono text-[12px] font-medium text-ink">
                {conn_endpoint()}
              </span>
              <span class="block text-[11px] text-muted">{conn_label(@connection)}</span>
            </span>
            <.icon name="hero-chevron-right" class="size-4 shrink-0 text-muted" />
          </.link>
        </div>

        <div :if={@has_hosts} class="px-3 pt-3">
          <button
            type="button"
            phx-click={JS.dispatch("cmdk:open")}
            class="flex w-full items-center gap-2 rounded-lg border border-rail bg-surface-soft px-2.5 py-2 text-[13px] text-muted hover:bg-canvas"
          >
            <.icon name="hero-magnifying-glass" class="size-4" />
            <span class="flex-1 text-left">Search &amp; run…</span>
            <kbd class="rounded border border-rail bg-surface px-1 text-[10px] font-medium">⌘K</kbd>
          </button>
        </div>

        <nav :if={@has_hosts} class="flex-1 overflow-y-auto px-3 py-4">
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

        <%!-- locked nav: until a host is connected, only onboarding + settings --%>
        <nav :if={!@has_hosts} class="flex-1 overflow-y-auto px-3 py-4">
          <p class="px-2.5 pb-1.5 text-[10px] font-semibold uppercase tracking-wider text-muted">
            Get started
          </p>
          <div class="space-y-0.5">
            <.nav_item
              icon="hero-server-stack"
              label="Connect a host"
              navigate={~p"/onboarding"}
              active={false}
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
          <%!-- fuse has no user identity (single shared token); show the real auth mode --%>
          <span class="flex items-center gap-1.5 truncate text-[11px] text-muted">
            <.icon name={auth_icon()} class="size-3.5" />
            {auth_label()}
          </span>
          <span class="flex-1"></span>
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

    <.command_palette />

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  The ⌘K command palette: a static, client-owned overlay (open/close, keyboard
  nav, and result rendering all live in the `.CmdK` colocated hook). The server
  side is `FuseWeb.CommandPalette` (an `on_mount` hook on the console
  live_session) which answers `palette_search` / `palette_exec`.

  `phx-update="ignore"` hands the inner DOM to the hook so LiveView re-renders of
  the shell never clobber the open state or the rendered results.
  """
  def command_palette(assigns) do
    ~H"""
    <div id="command-palette" phx-hook=".CmdK" phx-update="ignore">
      <div data-cmdk-root class="hidden">
        <div
          data-cmdk-overlay
          class="fixed inset-0 z-[60] bg-ink/40 backdrop-blur-[1px]"
          aria-hidden="true"
        />
        <div
          data-cmdk-panel
          role="dialog"
          aria-modal="true"
          aria-label="Command palette"
          class="fixed left-1/2 top-[12vh] z-[70] w-full max-w-xl -translate-x-1/2 overflow-hidden rounded-2xl border border-rail bg-surface shadow-2xl"
        >
          <div class="flex items-center gap-2.5 border-b border-rail px-4">
            <.icon name="hero-magnifying-glass" class="size-4 shrink-0 text-muted" />
            <input
              data-cmdk-input
              type="text"
              autocomplete="off"
              spellcheck="false"
              placeholder="Search environments or jump to a screen…"
              class="w-full bg-transparent py-3.5 text-[14px] text-ink placeholder:text-muted focus:outline-none"
            />
            <kbd class="shrink-0 rounded border border-rail bg-surface-soft px-1.5 py-0.5 text-[10px] font-medium text-muted">
              Esc
            </kbd>
          </div>
          <ul data-cmdk-list class="max-h-[52vh] overflow-y-auto p-1.5"></ul>
          <div
            data-cmdk-empty
            class="hidden px-4 py-10 text-center text-[13px] text-muted"
          >
            No matches.
          </div>
        </div>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".CmdK">
        const NAV = [
          {label: "Environments", to: "/environments"},
          {label: "Hosts", to: "/hosts"},
          {label: "Snapshots", to: "/snapshots"},
          {label: "Activity", to: "/activity"},
          {label: "Settings", to: "/settings"},
        ]

        const esc = (s) =>
          s == null ? "" : String(s).replace(/[&<>"]/g, (c) =>
            ({"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;"})[c])

        export default {
          mounted() {
            this.open = false
            this.cursor = 0
            this.items = []
            this.results = []
            // toggle visibility on a child inside the phx-update="ignore" subtree
            // so a server re-render of the shell can never re-hide an open palette
            this.root = this.el.querySelector("[data-cmdk-root]")
            this.overlay = this.el.querySelector("[data-cmdk-overlay]")
            this.input = this.el.querySelector("[data-cmdk-input]")
            this.list = this.el.querySelector("[data-cmdk-list]")
            this.empty = this.el.querySelector("[data-cmdk-empty]")

            this.onKey = (e) => {
              if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
                e.preventDefault()
                this.toggle()
              } else if (e.key === "Escape" && this.open) {
                this.close()
              }
            }
            this.onOpen = () => this.openPalette()
            window.addEventListener("keydown", this.onKey)
            window.addEventListener("cmdk:open", this.onOpen)

            this.overlay.addEventListener("click", () => this.close())
            this.input.addEventListener("input", () => this.onInput())
            this.input.addEventListener("keydown", (e) => this.onInputKey(e))

            this.handleEvent("palette_results", ({results}) => {
              this.results = results || []
              this.render()
            })
          },

          destroyed() {
            window.removeEventListener("keydown", this.onKey)
            window.removeEventListener("cmdk:open", this.onOpen)
          },

          toggle() {
            this.open ? this.close() : this.openPalette()
          },

          openPalette() {
            this.open = true
            // remember who had focus so we can restore it on close (a11y)
            this.opener = document.activeElement
            this.root.classList.remove("hidden")
            this.input.value = ""
            this.results = []
            this.cursor = 0
            this.render()
            this.input.focus()
          },

          close() {
            this.open = false
            this.root.classList.add("hidden")
            const opener = this.opener
            this.opener = null
            if (opener && opener.focus) opener.focus()
          },

          onInput() {
            const q = this.input.value.trim()
            this.cursor = 0
            if (q.length > 0) {
              this.pushEvent("palette_search", {query: q})
            } else {
              this.results = []
            }
            this.render()
          },

          navItems() {
            const q = this.input.value.trim().toLowerCase()
            const nav = q ? NAV.filter((n) => n.label.toLowerCase().includes(q)) : NAV
            return nav.map((n) => ({kind: "nav", label: n.label, to: n.to, hint: "Go"}))
          },

          envItems() {
            return this.results.map((r) => ({
              kind: "env",
              label: r.id,
              sub: r.task_id,
              state: r.state,
              to: "/environments/" + r.id,
              hint: "Open",
            }))
          },

          buildItems() {
            const items = [...this.navItems(), ...this.envItems()]
            const q = this.input.value.trim().toLowerCase()
            items.push({kind: "theme", label: "Toggle theme", hint: "Theme"})
            // keep the theme command only when it matches a non-empty query
            return q && !"toggle theme".includes(q)
              ? items.slice(0, -1)
              : items
          },

          render() {
            this.items = this.buildItems()
            if (this.cursor >= this.items.length) {
              this.cursor = Math.max(0, this.items.length - 1)
            }
            this.list.innerHTML = this.items.map((it, i) => this.itemHtml(it, i)).join("")
            this.empty.classList.toggle("hidden", this.items.length > 0)
            this.list.querySelectorAll("[data-cmdk-item]").forEach((el) => {
              const i = parseInt(el.dataset.index)
              el.addEventListener("click", () => {
                this.cursor = i
                this.activate()
              })
              el.addEventListener("mousemove", () => {
                if (this.cursor !== i) {
                  this.cursor = i
                  this.highlight()
                }
              })
            })
            this.highlight()
          },

          itemHtml(it, i) {
            const sub = it.sub
              ? `<span class="ml-2 truncate font-mono text-[11px] text-muted">${esc(it.sub)}</span>`
              : ""
            // labels carry no explicit color so the active row's text-brand-strong
            // (inherited) can recolor them; inactive rows inherit the default ink
            const left =
              it.kind === "env"
                ? `<span class="font-mono text-[13px]">${esc(it.label)}</span>${sub}`
                : `<span class="text-[13px]">${esc(it.label)}</span>`
            return `<li data-cmdk-item data-index="${i}" class="flex cursor-pointer items-center justify-between gap-2 rounded-lg px-3 py-2">
              <span class="flex min-w-0 items-center">${left}</span>
              <span class="shrink-0 text-[10px] uppercase tracking-wider text-muted">${esc(it.hint)}</span>
            </li>`
          },

          highlight() {
            this.list.querySelectorAll("[data-cmdk-item]").forEach((el, i) => {
              const on = i === this.cursor
              el.classList.toggle("bg-brand-soft", on)
              el.classList.toggle("text-brand-strong", on)
              // a brand ring is the primary, theme-independent selection cue
              // (bg-brand-soft alone is near-invisible against surface in dark)
              el.classList.toggle("ring-1", on)
              el.classList.toggle("ring-inset", on)
              el.classList.toggle("ring-brand", on)
            })
          },

          onInputKey(e) {
            if (e.key === "ArrowDown") {
              e.preventDefault()
              this.move(1)
            } else if (e.key === "ArrowUp") {
              e.preventDefault()
              this.move(-1)
            } else if (e.key === "Enter") {
              e.preventDefault()
              this.activate()
            }
          },

          move(d) {
            if (this.items.length === 0) return
            this.cursor = (this.cursor + d + this.items.length) % this.items.length
            this.highlight()
            const el = this.list.querySelector(`[data-index="${this.cursor}"]`)
            if (el) el.scrollIntoView({block: "nearest"})
          },

          activate() {
            const it = this.items[this.cursor]
            if (!it) return
            if (it.kind === "theme") {
              const cur = document.documentElement.getAttribute("data-theme")
              const next = cur === "dark" ? "light" : "dark"
              localStorage.setItem("phx:theme", next)
              document.documentElement.setAttribute("data-theme", next)
              this.close()
            } else if (it.to) {
              this.close()
              this.pushEvent("palette_exec", {action: "navigate", to: it.to})
            }
          },
        }
      </script>
    </div>
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

  # --- connection panel ---

  # the fuse endpoint as a compact host[:port] label, from the configured base_url
  defp conn_endpoint do
    case (Application.get_env(:fuse, Fuse.Client.HTTP) || [])[:base_url] do
      url when is_binary(url) and url != "" -> display_host(url)
      _ -> "fuse"
    end
  end

  defp display_host(url) do
    case URI.parse(url) do
      %URI{host: host, port: port} when is_binary(host) and host != "" ->
        if port && port not in [80, 443], do: "#{host}:#{port}", else: host

      _ ->
        url
    end
  end

  defp conn_dot(:ok), do: "bg-ok"
  defp conn_dot(:degraded), do: "bg-warn"
  defp conn_dot(:unreachable), do: "bg-bad"
  defp conn_dot(_), do: "bg-muted motion-safe:animate-pulse"

  defp conn_label(:ok), do: "Connected"
  defp conn_label(:degraded), do: "Degraded"
  defp conn_label(:unreachable), do: "Unreachable"
  defp conn_label(_), do: "Checking…"

  # honest auth mode for the footer (no per-user identity; one shared password)
  defp auth_label, do: if(FuseWeb.Auth.enforce?(), do: "Signed in", else: "Open access")

  defp auth_icon, do: if(FuseWeb.Auth.enforce?(), do: "hero-lock-closed", else: "hero-lock-open")
end
