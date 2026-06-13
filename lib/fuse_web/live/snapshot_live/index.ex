defmodule FuseWeb.SnapshotLive.Index do
  @moduledoc """
  Snapshots console: the list of VM snapshots, with state-filter pills and
  per-row restore/delete actions (each behind a confirm modal). Reads through
  `Fuse.Snapshots`; degrades to an error banner if fuse is unreachable.

  Creating snapshots is an environment-scoped operation
  (`POST /environments/:vm_id/snapshots`), so there is no create button here.
  """
  use FuseWeb, :live_view

  alias Fuse.Environments
  alias Fuse.Hosts
  alias Fuse.Snapshots
  alias FuseWeb.Layouts

  # Snapshot states, in the order the design shows them (mirrors Fuse.SnapshotState).
  @states ~w(creating ready restoring deleting error)

  @impl true
  def mount(_params, _session, socket) do
    {snapshots, load_error} = load_snapshots()

    {:ok,
     socket
     |> assign(:page_title, "Snapshots")
     |> assign(:filter, "all")
     |> assign(:states, @states)
     |> assign(:load_error, load_error)
     |> assign(:snapshots, snapshots)
     |> assign(:counts, sidebar_counts(snapshots))}
  end

  @impl true
  def handle_event("filter", %{"state" => state}, socket) do
    {:noreply, assign(socket, :filter, state)}
  end

  def handle_event("restore", %{"id" => id}, socket) do
    {:noreply, run_action(socket, fn -> Snapshots.restore(id) end, "Snapshot restore started.")}
  end

  def handle_event("delete_snapshot", %{"id" => id}, socket) do
    {:noreply, run_action(socket, fn -> Snapshots.delete(id) end, "Snapshot deleted.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.console current={:snapshots} counts={@counts} flash={@flash}>
      <div class="mx-auto w-full max-w-5xl px-8 py-7">
        <div class="flex items-start justify-between gap-4">
          <div>
            <h1 class="text-[22px] font-semibold tracking-tight">Snapshots</h1>
            <p class="mt-1 text-[13px] text-muted">
              VM snapshots
              <span class="text-rail-strong">·</span> {length(@snapshots)} total
            </p>
          </div>
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

        <div class="mt-5 flex flex-wrap items-center gap-2">
          <span class="mr-1 text-[11px] font-semibold uppercase tracking-wider text-muted">State</span>
          <.pill label="All" value="all" active={@filter == "all"} count={length(@snapshots)} />
          <.pill
            :for={state <- @states}
            label={String.capitalize(state)}
            value={state}
            active={@filter == state}
            count={count_for(@snapshots, state)}
          />
        </div>

        <div class="mt-4 overflow-hidden rounded-xl border border-rail bg-surface">
          <table class="w-full border-collapse text-left">
            <thead>
              <tr class="border-b border-rail bg-surface-soft text-[11px] font-semibold uppercase tracking-wider text-muted">
                <th class="px-5 py-3 font-semibold">Snapshot</th>
                <th class="px-5 py-3 font-semibold">State</th>
                <th class="px-5 py-3 font-semibold">Mode</th>
                <th class="px-5 py-3 font-semibold">Size</th>
                <th class="px-5 py-3 font-semibold">Created</th>
                <th class="px-5 py-3 text-right font-semibold">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={snapshot <- filtered(@snapshots, @filter)}
                id={"snapshot-#{snapshot.id}"}
                class="border-b border-rail transition last:border-0 hover:bg-surface-soft/60"
              >
                <td class="px-5 py-3.5">
                  <div class="font-mono text-[13px] font-medium text-ink">{snapshot.id}</div>
                  <div class="mt-0.5 font-mono text-[11px] text-muted">{snapshot.vm_id || "—"}</div>
                </td>
                <td class="px-5 py-3.5">
                  <Layouts.badge label={label_for(snapshot.state)} color={badge_color(snapshot.state)} />
                </td>
                <td class="px-5 py-3.5 text-[12px] text-ink/80">{snapshot.mode || "—"}</td>
                <td class="px-5 py-3.5 font-mono text-[12px] text-ink/80">{humanize_size(snapshot.size_bytes)}</td>
                <td class="px-5 py-3.5 font-mono text-[12px] text-muted">{format_dt(snapshot.created_at)}</td>
                <td class="px-5 py-3.5">
                  <div class="flex items-center justify-end gap-1.5">
                    <button
                      type="button"
                      phx-click={Layouts.show_modal("confirm-restore-#{snapshot.id}")}
                      class="rounded-md border border-rail bg-surface px-2.5 py-1 text-[12px] font-medium text-ink/80 transition hover:bg-surface-soft"
                    >
                      Restore
                    </button>
                    <button
                      type="button"
                      phx-click={Layouts.show_modal("confirm-delete-#{snapshot.id}")}
                      class="rounded-md border border-bad/30 bg-bad-soft px-2.5 py-1 text-[12px] font-medium text-bad transition hover:bg-bad/10"
                    >
                      Delete
                    </button>
                  </div>

                  <Layouts.modal id={"confirm-restore-#{snapshot.id}"}>
                    <:title>Restore snapshot</:title>
                    <p class="text-[13px] text-muted">
                      Restore <span class="font-mono text-ink">{snapshot.id}</span>? This rolls the
                      environment back to this snapshot.
                    </p>
                    <:actions>
                      <button
                        type="button"
                        phx-click={Layouts.hide_modal("confirm-restore-#{snapshot.id}")}
                        class="rounded-lg border border-rail bg-surface px-3 py-1.5 text-[13px] font-medium text-ink/80 hover:bg-surface-soft"
                      >
                        Cancel
                      </button>
                      <button
                        type="button"
                        phx-click={Layouts.hide_modal("confirm-restore-#{snapshot.id}") |> JS.push("restore")}
                        phx-value-id={snapshot.id}
                        class="rounded-lg bg-brand px-3 py-1.5 text-[13px] font-medium text-white hover:bg-brand-strong"
                      >
                        Restore
                      </button>
                    </:actions>
                  </Layouts.modal>

                  <Layouts.modal id={"confirm-delete-#{snapshot.id}"}>
                    <:title>Delete snapshot</:title>
                    <p class="text-[13px] text-muted">
                      Delete <span class="font-mono text-ink">{snapshot.id}</span>? This can't be undone.
                    </p>
                    <:actions>
                      <button
                        type="button"
                        phx-click={Layouts.hide_modal("confirm-delete-#{snapshot.id}")}
                        class="rounded-lg border border-rail bg-surface px-3 py-1.5 text-[13px] font-medium text-ink/80 hover:bg-surface-soft"
                      >
                        Cancel
                      </button>
                      <button
                        type="button"
                        phx-click={Layouts.hide_modal("confirm-delete-#{snapshot.id}") |> JS.push("delete_snapshot")}
                        phx-value-id={snapshot.id}
                        class="rounded-lg bg-bad px-3 py-1.5 text-[13px] font-medium text-white hover:bg-bad/90"
                      >
                        Delete
                      </button>
                    </:actions>
                  </Layouts.modal>
                </td>
              </tr>
              <tr :if={filtered(@snapshots, @filter) == []}>
                <td colspan="6" class="px-5 py-16 text-center text-[13px] text-muted">
                  {empty_message(@filter, @load_error)}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </Layouts.console>
    """
  end

  # --- components ---

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :active, :boolean, required: true
  attr :count, :integer, required: true

  defp pill(assigns) do
    ~H"""
    <button
      phx-click="filter"
      phx-value-state={@value}
      class={[
        "inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-[12px] font-medium ring-1 transition",
        (@active && "bg-ink text-canvas ring-ink") ||
          "bg-surface text-ink/70 ring-rail hover:bg-surface-soft"
      ]}
    >
      <span :if={@value != "all"} class={["size-1.5 rounded-full", dot_class(@value)]} />
      {@label}
      <span class={["tabular-nums", (@active && "text-canvas/70") || "text-muted"]}>{@count}</span>
    </button>
    """
  end

  # --- actions ---

  # Run a snapshot action, then reload the list and flash. Tolerant of
  # `{:error, %Fuse.Error{}}` — never crashes the LiveView.
  defp run_action(socket, fun, ok_message) do
    case fun.() do
      {:ok, _} ->
        {snapshots, load_error} = load_snapshots()

        socket
        |> assign(:snapshots, snapshots)
        |> assign(:load_error, load_error)
        |> assign(:counts, sidebar_counts(snapshots))
        |> put_flash(:info, ok_message)

      {:error, %Fuse.Error{} = error} ->
        put_flash(socket, :error, error.message)
    end
  end

  # --- data ---

  defp load_snapshots do
    case Snapshots.list() do
      {:ok, snapshots} -> {snapshots, nil}
      {:error, error} -> {[], error}
    end
  end

  defp sidebar_counts(snapshots) do
    %{
      environments: safe_count(fn -> Environments.list() end),
      hosts: safe_count(&Hosts.list/0),
      snapshots: length(snapshots)
    }
  end

  defp safe_count(fun) do
    case fun.() do
      {:ok, list} -> length(list)
      _ -> nil
    end
  end

  defp filtered(snapshots, "all"), do: snapshots
  defp filtered(snapshots, state), do: Enum.filter(snapshots, &(&1.state == state))

  defp count_for(snapshots, state), do: Enum.count(snapshots, &(&1.state == state))

  # --- formatting ---

  defp humanize_size(nil), do: "—"

  defp humanize_size(bytes) when is_integer(bytes),
    do: humanize_size(bytes, ["B", "KB", "MB", "GB", "TB", "PB"])

  defp humanize_size(_), do: "—"

  defp humanize_size(bytes, [unit]), do: "#{trim_float(round_size(bytes))} #{unit}"

  defp humanize_size(bytes, [unit | rest]) do
    if bytes < 1024 do
      "#{trim_float(round_size(bytes))} #{unit}"
    else
      humanize_size(bytes / 1024, rest)
    end
  end

  defp round_size(bytes) when is_float(bytes), do: Float.round(bytes, 1)
  defp round_size(bytes), do: bytes

  defp trim_float(number) when is_float(number) do
    if number == trunc(number), do: trunc(number), else: number
  end

  defp trim_float(number), do: number

  defp format_dt(nil), do: "—"
  defp format_dt(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  defp label_for(nil), do: "Unknown"
  defp label_for(state), do: String.capitalize(state)

  defp dot_class("ready"), do: "bg-ok"
  defp dot_class("creating"), do: "bg-warn"
  defp dot_class("restoring"), do: "bg-warn"
  defp dot_class("deleting"), do: "bg-warn"
  defp dot_class("error"), do: "bg-bad"
  defp dot_class(_), do: "bg-muted"

  defp badge_color("ready"), do: :ok
  defp badge_color("creating"), do: :warn
  defp badge_color("restoring"), do: :warn
  defp badge_color("deleting"), do: :warn
  defp badge_color("error"), do: :bad
  defp badge_color(_), do: :muted

  defp empty_message(_filter, %Fuse.Error{}), do: "No snapshots to show."
  defp empty_message("all", _), do: "No snapshots yet."
  defp empty_message(state, _), do: "No #{state} snapshots."
end
