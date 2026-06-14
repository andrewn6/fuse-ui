defmodule FuseWeb.EnvironmentLive.Show do
  @moduledoc """
  Environment detail: spec, connection URL, lifecycle actions, and a live event
  log fed by the fuse SSE stream (via `Fuse.EventStream` -> `Phoenix.PubSub`).

  On a connected mount we `subscribe/1` to the env's topic and `watch/1` it with
  `subscriber: self()`. The consumer monitors this LiveView and self-stops only
  when its last viewer leaves, so closing one tab never tears down the stream for
  other viewers, and an abandoned stream doesn't linger. Incoming `%Event{}`s
  update the live state badge / URL and prepend to the log.
  """
  use FuseWeb, :live_view

  alias Fuse.Environments
  alias Fuse.EventStream
  alias Fuse.State
  alias FuseWeb.Layouts

  import FuseWeb.Layouts, only: [show_modal: 1, hide_modal: 1]

  # cap the in-memory log so a long-lived running env can't grow it unbounded
  @max_log 200

  # states from which an environment may still be drained
  @drainable ~w(provisioning running)

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Environments.get(id) do
      {:ok, env} ->
        if connected?(socket) do
          EventStream.subscribe(id)
          EventStream.watch(id, subscriber: self())
        end

        {:ok,
         socket
         |> assign(:page_title, env.id)
         |> assign(:id, id)
         |> assign(:env, env)
         |> assign(:not_found, false)
         |> assign(:load_error, nil)
         |> assign(:stream_down, nil)
         |> assign(:streaming, connected?(socket))
         |> assign(:events, [])}

      {:error, %Fuse.Error{code: "not_found"} = error} ->
        {:ok, assign_missing(socket, id, error, true)}

      {:error, %Fuse.Error{} = error} ->
        {:ok, assign_missing(socket, id, error, false)}
    end
  end

  defp assign_missing(socket, id, error, not_found?) do
    socket
    |> assign(:page_title, "Environment")
    |> assign(:id, id)
    |> assign(:env, nil)
    |> assign(:not_found, not_found?)
    |> assign(:load_error, error)
    |> assign(:stream_down, nil)
    |> assign(:streaming, false)
    |> assign(:events, [])
  end

  @impl true
  def handle_info({:environment_event, %EventStream.Event{} = event}, socket) do
    {:noreply,
     socket
     |> update(:env, &apply_event(&1, event))
     |> update(:events, fn events -> Enum.take([event | events], @max_log) end)
     |> assign(:stream_down, nil)}
  end

  def handle_info({:environment_stream_down, _vm_id, %Fuse.Error{} = error}, socket) do
    {:noreply, socket |> assign(:stream_down, error) |> assign(:streaming, false)}
  end

  @impl true
  def handle_event("drain", %{"id" => id}, socket) do
    {:noreply, run_action(socket, fn -> Environments.drain(id) end, "Environment draining.")}
  end

  def handle_event("rotate_token", %{"id" => id}, socket) do
    {:noreply, run_action(socket, fn -> Environments.rotate_token(id) end, "Token rotated.")}
  end

  def handle_event("destroy", %{"id" => id}, socket) do
    case Environments.destroy(id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Environment destroyed.")
         |> push_navigate(to: ~p"/environments")}

      {:error, %Fuse.Error{} = error} ->
        {:noreply, put_flash(socket, :error, error.message)}
    end
  end

  @impl true
  def render(%{env: nil} = assigns) do
    ~H"""
    <Layouts.console current={:environments} connection={@connection} flash={@flash}>
      <div class="mx-auto w-full max-w-2xl px-8 py-16 text-center">
        <div class="mx-auto flex size-12 items-center justify-center rounded-xl bg-bad-soft">
          <.icon name="hero-exclamation-triangle" class="size-6 text-bad" />
        </div>
        <h1 class="mt-4 text-[18px] font-semibold">
          {(@not_found && "Environment not found") || "Couldn't load environment"}
        </h1>
        <p class="mt-1 font-mono text-[13px] text-muted">{@id}</p>
        <p class="mt-2 text-[13px] text-muted">{@load_error && @load_error.message}</p>
        <.link
          navigate={~p"/environments"}
          class="mt-6 inline-flex items-center gap-1.5 rounded-lg border border-rail bg-surface px-3.5 py-2 text-[13px] font-medium hover:bg-surface-soft"
        >
          <.icon name="hero-arrow-left" class="size-4" /> Back to Environments
        </.link>
      </div>
    </Layouts.console>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.console current={:environments} connection={@connection} flash={@flash}>
      <div class="border-b border-rail bg-surface px-8 py-5">
        <.link
          navigate={~p"/environments"}
          class="inline-flex items-center gap-1.5 text-[12px] font-medium text-muted hover:text-ink"
        >
          <.icon name="hero-arrow-left" class="size-3.5" /> Environments
        </.link>

        <div class="mt-3 flex flex-wrap items-start justify-between gap-4">
          <div class="min-w-0">
            <div class="flex items-center gap-2">
              <h1 class="truncate font-mono text-[20px] font-semibold tracking-tight">{@env.id}</h1>
              <.copy_button id={"copy-env-#{@env.id}"} value={@env.id} />
              <Layouts.badge label={label_for(@env.state)} color={state_color(@env.state)} />
              <span
                :if={@streaming and State.active?(@env.state)}
                role="status"
                aria-live="polite"
                class="inline-flex items-center gap-1.5 rounded-full bg-ok-soft px-2 py-0.5 text-[11px] font-medium text-ok"
              >
                <span class="size-1.5 rounded-full bg-ok motion-safe:animate-pulse" />
                <span>Live</span>
                <span class="sr-only">Receiving live events</span>
              </span>
            </div>
            <p class="mt-1 text-[13px] text-muted">
              <span class="font-mono">{@env.task_id || "no task"}</span>
              <span class="text-rail-strong">·</span>
              host <span class="font-mono">{@env.host_id || "unassigned"}</span>
              <span class="text-rail-strong">·</span>
              created {fmt_datetime(@env.created_at)}
            </p>
          </div>

          <div class="flex shrink-0 items-center gap-1.5">
            <button
              :if={drainable?(@env.state)}
              type="button"
              phx-click={show_modal("confirm-drain")}
              class="rounded-md border border-rail bg-surface px-2.5 py-1.5 text-[12px] font-medium text-ink hover:bg-surface-soft"
            >
              Drain
            </button>
            <button
              type="button"
              phx-click={show_modal("confirm-rotate")}
              class="rounded-md border border-rail bg-surface px-2.5 py-1.5 text-[12px] font-medium text-ink hover:bg-surface-soft"
            >
              Rotate token
            </button>
            <button
              type="button"
              phx-click={show_modal("confirm-destroy")}
              class="rounded-md border border-bad/30 bg-bad-soft px-2.5 py-1.5 text-[12px] font-medium text-bad hover:bg-bad/10"
            >
              Destroy
            </button>
          </div>
        </div>
      </div>

      <div class="mx-auto grid w-full max-w-5xl grid-cols-1 gap-6 px-8 py-7 lg:grid-cols-3">
        <div class="space-y-6 lg:col-span-1">
          <section class="overflow-hidden rounded-xl border border-rail bg-surface">
            <h2 class="border-b border-rail px-5 py-3 text-[11px] font-semibold uppercase tracking-wider text-muted">
              Spec
            </h2>
            <dl class="divide-y divide-rail">
              <.spec_row label="vCPU" value={cpu(@env.spec)} />
              <.spec_row label="Memory" value={ram(@env.spec)} />
              <.spec_row label="Storage" value={storage(@env.spec)} />
              <.spec_row label="Region" value={region(@env.spec)} />
              <.spec_row label="Max runtime" value={runtime(@env.spec)} />
            </dl>
          </section>

          <section :if={@env.url} class="overflow-hidden rounded-xl border border-rail bg-surface">
            <h2 class="border-b border-rail px-5 py-3 text-[11px] font-semibold uppercase tracking-wider text-muted">
              Connection
            </h2>
            <div class="flex items-center gap-2 px-5 py-3.5">
              <a
                href={@env.url}
                target="_blank"
                rel="noopener"
                class="min-w-0 flex-1 truncate font-mono text-[12px] text-brand-strong hover:underline"
              >
                {@env.url}
              </a>
              <.copy_button id="copy-url" value={@env.url} />
            </div>
          </section>

          <section
            :if={@env.error}
            class="overflow-hidden rounded-xl border border-bad/30 bg-bad-soft"
          >
            <h2 class="border-b border-bad/20 px-5 py-3 text-[11px] font-semibold uppercase tracking-wider text-bad">
              Error
            </h2>
            <p class="px-5 py-3.5 font-mono text-[12px] text-bad">{@env.error}</p>
          </section>
        </div>

        <section class="overflow-hidden rounded-xl border border-rail bg-surface lg:col-span-2">
          <div class="flex items-center justify-between border-b border-rail px-5 py-3">
            <h2 class="text-[11px] font-semibold uppercase tracking-wider text-muted">Event log</h2>
            <span class="text-[11px] tabular-nums text-muted">{length(@events)} events</span>
          </div>

          <div
            :if={@stream_down}
            role="status"
            aria-live="polite"
            class="flex items-start gap-2.5 border-b border-rail bg-warn-soft px-5 py-3 text-[12px]"
          >
            <.icon name="hero-signal-slash" class="mt-0.5 size-4 shrink-0 text-warn" />
            <div>
              <p class="font-medium text-warn">Event stream disconnected</p>
              <p class="text-muted">{@stream_down.message}</p>
            </div>
          </div>

          <ol class="divide-y divide-rail">
            <li :for={event <- @events} class="flex items-start gap-3 px-5 py-3">
              <span class="mt-0.5 w-[68px] shrink-0 font-mono text-[11px] tabular-nums text-muted">
                {fmt_time(event.updated_at)}
              </span>
              <div class="min-w-0">
                <Layouts.badge label={label_for(event.state)} color={state_color(event.state)} />
                <p :if={event.url} class="mt-1 truncate font-mono text-[11px] text-muted">
                  {event.url}
                </p>
                <p :if={event.error} class="mt-1 font-mono text-[11px] text-bad">{event.error}</p>
              </div>
            </li>
            <li :if={@events == []} class="px-5 py-12 text-center text-[13px] text-muted">
              <span :if={@streaming}>Waiting for events…</span>
              <span :if={not @streaming}>Connecting…</span>
            </li>
          </ol>
        </section>
      </div>

      <Layouts.modal id="confirm-drain">
        <:title>Drain environment</:title>
        <p class="text-[13px] text-muted">
          Gracefully stop <span class="font-mono text-ink">{@env.id}</span>. In-flight work is allowed to finish; no new work is scheduled.
        </p>
        <:actions>
          <button
            type="button"
            phx-click={hide_modal("confirm-drain")}
            class="rounded-lg border border-rail bg-surface px-3 py-1.5 text-[13px] font-medium text-ink hover:bg-surface-soft"
          >
            Cancel
          </button>
          <button
            type="button"
            phx-click={hide_modal("confirm-drain") |> JS.push("drain", value: %{id: @env.id})}
            class="rounded-lg bg-warn px-3 py-1.5 text-[13px] font-medium text-white hover:opacity-90"
          >
            Drain
          </button>
        </:actions>
      </Layouts.modal>

      <Layouts.modal id="confirm-rotate">
        <:title>Rotate token</:title>
        <p class="text-[13px] text-muted">
          Issue a fresh guest token for <span class="font-mono text-ink">{@env.id}</span>. The previous token stops working immediately.
        </p>
        <:actions>
          <button
            type="button"
            phx-click={hide_modal("confirm-rotate")}
            class="rounded-lg border border-rail bg-surface px-3 py-1.5 text-[13px] font-medium text-ink hover:bg-surface-soft"
          >
            Cancel
          </button>
          <button
            type="button"
            phx-click={hide_modal("confirm-rotate") |> JS.push("rotate_token", value: %{id: @env.id})}
            class="rounded-lg bg-brand px-3 py-1.5 text-[13px] font-medium text-white hover:bg-brand-strong"
          >
            Rotate token
          </button>
        </:actions>
      </Layouts.modal>

      <Layouts.modal id="confirm-destroy">
        <:title>Destroy environment</:title>
        <p class="text-[13px] text-muted">
          Permanently destroy <span class="font-mono text-ink">{@env.id}</span>. This can't be undone.
        </p>
        <:actions>
          <button
            type="button"
            phx-click={hide_modal("confirm-destroy")}
            class="rounded-lg border border-rail bg-surface px-3 py-1.5 text-[13px] font-medium text-ink hover:bg-surface-soft"
          >
            Cancel
          </button>
          <button
            type="button"
            phx-click={hide_modal("confirm-destroy") |> JS.push("destroy", value: %{id: @env.id})}
            class="rounded-lg bg-bad px-3 py-1.5 text-[13px] font-medium text-white hover:opacity-90"
          >
            Destroy
          </button>
        </:actions>
      </Layouts.modal>
    </Layouts.console>
    """
  end

  # --- components ---

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp spec_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between px-5 py-3">
      <dt class="text-[12px] text-muted">{@label}</dt>
      <dd class="font-mono text-[13px] text-ink">{@value}</dd>
    </div>
    """
  end

  # --- actions ---

  # run a lifecycle action, then refresh the env + flash. errors surface as a
  # flash; we never crash the LiveView. (drain/rotate state changes also arrive
  # via the live stream, but a refresh makes the update immediate.)
  defp run_action(socket, fun, success_message) do
    case fun.() do
      {:ok, _} -> socket |> refresh_env() |> put_flash(:info, success_message)
      {:error, %Fuse.Error{} = error} -> put_flash(socket, :error, error.message)
    end
  end

  defp refresh_env(socket) do
    case Environments.get(socket.assigns.id) do
      {:ok, env} -> assign(socket, :env, env)
      {:error, _} -> socket
    end
  end

  # fold an incoming event into the env we're displaying. only overwrite a field
  # when the event carries a value, so a sparse event can't blank the URL/error.
  defp apply_event(nil, _event), do: nil

  defp apply_event(env, event) do
    %{
      env
      | state: event.state || env.state,
        url: event.url || env.url,
        error: event.error || env.error,
        updated_at: event.updated_at || env.updated_at
    }
  end

  # --- formatting ---

  defp drainable?(state), do: state in @drainable

  defp state_color(state) do
    cond do
      State.running?(state) -> :ok
      state in ~w(provisioning draining) -> :warn
      state in ~w(destroying destroyed failed) -> :bad
      true -> :muted
    end
  end

  defp label_for(nil), do: "Unknown"
  defp label_for(state), do: String.capitalize(state)

  defp cpu(%Fuse.ResourceSpec{cpus: c}) when is_integer(c), do: "#{c}"
  defp cpu(_), do: "—"

  defp ram(%Fuse.ResourceSpec{ram_mb: mb}) when is_integer(mb) and mb >= 1024,
    do: "#{trim_float(Float.round(mb / 1024, 1))} GB"

  defp ram(%Fuse.ResourceSpec{ram_mb: mb}) when is_integer(mb), do: "#{mb} MB"
  defp ram(_), do: "—"

  defp storage(%Fuse.ResourceSpec{storage_gb: gb}) when is_integer(gb), do: "#{gb} GB"
  defp storage(_), do: "—"

  defp region(%Fuse.ResourceSpec{region: r}) when is_binary(r) and r != "", do: r
  defp region(_), do: "—"

  defp runtime(%Fuse.ResourceSpec{max_runtime_seconds: s}) when is_integer(s) and s > 0,
    do: fmt_duration(s)

  defp runtime(_), do: "—"

  defp fmt_duration(s) when s >= 3600, do: "#{trim_float(Float.round(s / 3600, 1))} h"
  defp fmt_duration(s) when s >= 60, do: "#{div(s, 60)} min"
  defp fmt_duration(s), do: "#{s} s"

  defp fmt_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
  defp fmt_datetime(_), do: "—"

  defp fmt_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M:%S")
  defp fmt_time(_), do: "—"

  defp trim_float(float) when float == trunc(float), do: trunc(float)
  defp trim_float(float), do: float
end
