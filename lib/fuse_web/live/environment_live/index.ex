defmodule FuseWeb.EnvironmentLive.Index do
  @moduledoc """
  Environments console: the list of sandboxed microVM environments, with
  state-filter pills and per-row spec/state/task/host. Reads through
  `Fuse.Environments`; degrades to an error banner if fuse is unreachable.
  """
  use FuseWeb, :live_view

  alias Fuse.Environments
  alias Fuse.Hosts
  alias Fuse.Plan
  alias Fuse.Snapshots
  alias FuseWeb.Layouts

  import FuseWeb.Layouts, only: [show_modal: 1, hide_modal: 1]

  # Stored (non-terminal) states, in the order the design shows them.
  @states ~w(provisioning running draining destroying)

  # States from which an environment may still be drained.
  @drainable ~w(provisioning running)

  @impl true
  def mount(_params, _session, socket) do
    {environments, load_error} = load_environments()

    {:ok,
     socket
     |> assign(:page_title, "Environments")
     |> assign(:filter, "all")
     |> assign(:states, @states)
     |> assign(:plans, Plan.names())
     |> assign(:load_error, load_error)
     |> assign(:environments, environments)
     |> assign(:counts, sidebar_counts(environments))
     |> assign(:show_create, false)
     |> assign(:form, create_form())}
  end

  @impl true
  def handle_event("filter", %{"state" => state}, socket) do
    {:noreply, assign(socket, :filter, state)}
  end

  def handle_event("open_create", _params, socket) do
    {:noreply, socket |> assign(:show_create, true) |> assign(:form, create_form())}
  end

  def handle_event("close_create", _params, socket) do
    {:noreply, assign(socket, :show_create, false)}
  end

  def handle_event("create_environment", %{"environment" => attrs}, socket) do
    case create_environment(attrs) do
      {:ok, _env} ->
        {:noreply,
         socket
         |> reload()
         |> assign(:show_create, false)
         |> assign(:form, create_form())
         |> put_flash(:info, "Environment created.")}

      {:error, %Fuse.Error{} = error} ->
        {:noreply, put_flash(socket, :error, error.message)}
    end
  end

  def handle_event("drain", %{"id" => id}, socket) do
    {:noreply, run_action(socket, fn -> Environments.drain(id) end, "Environment draining.")}
  end

  def handle_event("rotate_token", %{"id" => id}, socket) do
    {:noreply, run_action(socket, fn -> Environments.rotate_token(id) end, "Token rotated.")}
  end

  def handle_event("destroy", %{"id" => id}, socket) do
    {:noreply, run_action(socket, fn -> Environments.destroy(id) end, "Environment destroyed.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.console current={:environments} counts={@counts} flash={@flash}>
      <div class="mx-auto w-full max-w-5xl px-8 py-7">
        <div class="flex items-start justify-between gap-4">
          <div>
            <h1 class="text-[22px] font-semibold tracking-tight">Environments</h1>
            <p class="mt-1 text-[13px] text-muted">
              Sandboxed VM environments for agent tasks
              <span class="text-rail-strong">·</span> {length(@environments)} total
            </p>
          </div>
          <button
            phx-click="open_create"
            class="inline-flex shrink-0 items-center gap-1.5 rounded-lg bg-brand px-3.5 py-2 text-[13px] font-medium text-white shadow-sm transition hover:bg-brand-strong"
          >
            <.icon name="hero-plus" class="size-4" /> Create environment
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

        <div class="mt-5 flex flex-wrap items-center gap-2">
          <span class="mr-1 text-[11px] font-semibold uppercase tracking-wider text-muted">State</span>
          <.pill label="All" value="all" active={@filter == "all"} count={length(@environments)} />
          <.pill
            :for={state <- @states}
            label={String.capitalize(state)}
            value={state}
            active={@filter == state}
            count={count_for(@environments, state)}
          />
        </div>

        <div class="mt-4 overflow-hidden rounded-xl border border-rail bg-surface">
          <table class="w-full border-collapse text-left">
            <thead>
              <tr class="border-b border-rail bg-surface-soft text-[11px] font-semibold uppercase tracking-wider text-muted">
                <th class="px-5 py-3 font-semibold">Environment</th>
                <th class="px-5 py-3 font-semibold">State</th>
                <th class="px-5 py-3 font-semibold">Task</th>
                <th class="px-5 py-3 font-semibold">Host</th>
                <th class="px-5 py-3 text-right font-semibold">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={env <- filtered(@environments, @filter)}
                id={"env-#{env.id}"}
                class="border-b border-rail transition last:border-0 hover:bg-surface-soft/60"
              >
                <td class="px-5 py-3.5">
                  <div class="font-mono text-[13px] font-medium text-ink">{env.id}</div>
                  <div class="mt-0.5 font-mono text-[11px] text-muted">{spec_label(env.spec)}</div>
                </td>
                <td class="px-5 py-3.5"><.state_badge state={env.state} /></td>
                <td class="px-5 py-3.5 font-mono text-[12px] text-ink/80">{env.task_id || "—"}</td>
                <td class="px-5 py-3.5 font-mono text-[12px] text-muted">{env.host_id || "—"}</td>
                <td class="px-5 py-3.5">
                  <.row_actions env={env} />
                </td>
              </tr>
              <tr :if={filtered(@environments, @filter) == []}>
                <td colspan="5" class="px-5 py-16 text-center text-[13px] text-muted">
                  {empty_message(@filter, @load_error)}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <.create_modal :if={@show_create} form={@form} plans={@plans} />

      <Layouts.modal :for={env <- @environments} id={"confirm-drain-#{env.id}"}>
        <:title>Drain environment</:title>
        <p class="text-[13px] text-muted">
          Gracefully stop
          <span class="font-mono text-ink">{env.id}</span>. In-flight work is allowed to finish; no new work is scheduled.
        </p>
        <:actions>
          <button
            type="button"
            phx-click={hide_modal("confirm-drain-#{env.id}")}
            class="rounded-lg border border-rail bg-surface px-3 py-1.5 text-[13px] font-medium text-ink hover:bg-surface-soft"
          >
            Cancel
          </button>
          <button
            type="button"
            phx-click={hide_modal("confirm-drain-#{env.id}") |> JS.push("drain", value: %{id: env.id})}
            class="rounded-lg bg-warn px-3 py-1.5 text-[13px] font-medium text-white hover:opacity-90"
          >
            Drain
          </button>
        </:actions>
      </Layouts.modal>

      <Layouts.modal :for={env <- @environments} id={"confirm-rotate-#{env.id}"}>
        <:title>Rotate token</:title>
        <p class="text-[13px] text-muted">
          Issue a fresh guest token for
          <span class="font-mono text-ink">{env.id}</span>. The previous token stops working immediately.
        </p>
        <:actions>
          <button
            type="button"
            phx-click={hide_modal("confirm-rotate-#{env.id}")}
            class="rounded-lg border border-rail bg-surface px-3 py-1.5 text-[13px] font-medium text-ink hover:bg-surface-soft"
          >
            Cancel
          </button>
          <button
            type="button"
            phx-click={hide_modal("confirm-rotate-#{env.id}") |> JS.push("rotate_token", value: %{id: env.id})}
            class="rounded-lg bg-brand px-3 py-1.5 text-[13px] font-medium text-white hover:bg-brand-strong"
          >
            Rotate token
          </button>
        </:actions>
      </Layouts.modal>

      <Layouts.modal :for={env <- @environments} id={"confirm-destroy-#{env.id}"}>
        <:title>Destroy environment</:title>
        <p class="text-[13px] text-muted">
          Permanently destroy
          <span class="font-mono text-ink">{env.id}</span>. This can't be undone.
        </p>
        <:actions>
          <button
            type="button"
            phx-click={hide_modal("confirm-destroy-#{env.id}")}
            class="rounded-lg border border-rail bg-surface px-3 py-1.5 text-[13px] font-medium text-ink hover:bg-surface-soft"
          >
            Cancel
          </button>
          <button
            type="button"
            phx-click={hide_modal("confirm-destroy-#{env.id}") |> JS.push("destroy", value: %{id: env.id})}
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

  attr :state, :string, required: true

  defp state_badge(assigns) do
    {dot, text, bg} = badge_classes(assigns.state)
    assigns = assign(assigns, dot: dot, text: text, bg: bg)

    ~H"""
    <span class={["inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[12px] font-medium", @bg, @text]}>
      <span class={["size-1.5 rounded-full", @dot]} />
      {label_for(@state)}
    </span>
    """
  end

  attr :env, :map, required: true

  defp row_actions(assigns) do
    ~H"""
    <div class="flex items-center justify-end gap-1.5">
      <button
        :if={drainable?(@env.state)}
        type="button"
        phx-click={show_modal("confirm-drain-#{@env.id}")}
        class="rounded-md border border-rail bg-surface px-2.5 py-1 text-[12px] font-medium text-ink hover:bg-surface-soft"
      >
        Drain
      </button>
      <button
        type="button"
        phx-click={show_modal("confirm-rotate-#{@env.id}")}
        class="rounded-md border border-rail bg-surface px-2.5 py-1 text-[12px] font-medium text-ink hover:bg-surface-soft"
      >
        Rotate token
      </button>
      <button
        type="button"
        phx-click={show_modal("confirm-destroy-#{@env.id}")}
        class="rounded-md border border-bad/30 bg-bad-soft px-2.5 py-1 text-[12px] font-medium text-bad hover:bg-bad/10"
      >
        Destroy
      </button>
    </div>
    """
  end

  attr :form, :any, required: true
  attr :plans, :list, required: true

  defp create_modal(assigns) do
    ~H"""
    <div class="relative z-50" id="create-environment">
      <div class="fixed inset-0 bg-ink/40 transition-opacity" aria-hidden="true" />
      <div
        class="fixed inset-0 flex items-center justify-center overflow-y-auto p-4"
        role="dialog"
        aria-modal="true"
        aria-labelledby="create-environment-title"
      >
        <div
          phx-click-away="close_create"
          phx-window-keydown="close_create"
          phx-key="escape"
          class="w-full max-w-md rounded-2xl border border-rail bg-surface shadow-lg"
        >
          <div class="flex items-start justify-between gap-4 px-5 pt-5">
            <h2 id="create-environment-title" class="text-[15px] font-semibold text-ink">
              Create environment
            </h2>
            <button
              type="button"
              phx-click="close_create"
              class="-mr-1 -mt-1 rounded-md p-1 text-muted hover:bg-surface-soft hover:text-ink"
              aria-label="Close"
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </div>

          <.form for={@form} phx-submit="create_environment">
            <div class="space-y-4 px-5 py-4">
              <div>
                <label for="environment_task_id" class="block text-[12px] font-medium text-ink">
                  Task ID
                </label>
                <input
                  type="text"
                  id="environment_task_id"
                  name="environment[task_id]"
                  value={@form[:task_id].value}
                  required
                  placeholder="task_…"
                  class="mt-1 block w-full rounded-lg border border-rail bg-canvas px-3 py-2 font-mono text-[13px] text-ink placeholder:text-muted focus:border-brand focus:outline-none"
                />
              </div>

              <div>
                <label for="environment_plan" class="block text-[12px] font-medium text-ink">
                  Plan
                </label>
                <select
                  id="environment_plan"
                  name="environment[plan]"
                  class="mt-1 block w-full rounded-lg border border-rail bg-canvas px-3 py-2 text-[13px] text-ink focus:border-brand focus:outline-none"
                >
                  <option :for={plan <- @plans} value={plan} selected={@form[:plan].value == plan}>
                    {String.capitalize(plan)} · {plan_summary(plan)}
                  </option>
                </select>
              </div>

              <div>
                <label for="environment_region" class="block text-[12px] font-medium text-ink">
                  Region <span class="font-normal text-muted">(optional)</span>
                </label>
                <input
                  type="text"
                  id="environment_region"
                  name="environment[region]"
                  value={@form[:region].value}
                  placeholder="us-east-1"
                  class="mt-1 block w-full rounded-lg border border-rail bg-canvas px-3 py-2 text-[13px] text-ink placeholder:text-muted focus:border-brand focus:outline-none"
                />
              </div>
            </div>

            <div class="flex items-center justify-end gap-2 border-t border-rail px-5 py-3.5">
              <button
                type="button"
                phx-click="close_create"
                class="rounded-lg border border-rail bg-surface px-3 py-1.5 text-[13px] font-medium text-ink hover:bg-surface-soft"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="rounded-lg bg-brand px-3.5 py-1.5 text-[13px] font-medium text-white shadow-sm hover:bg-brand-strong"
              >
                Create environment
              </button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  # --- data ---

  defp load_environments do
    case Environments.list() do
      {:ok, environments} -> {environments, nil}
      {:error, error} -> {[], error}
    end
  end

  # Reload the list and recompute the sidebar counts after a mutation.
  defp reload(socket) do
    {environments, load_error} = load_environments()

    socket
    |> assign(:environments, environments)
    |> assign(:load_error, load_error)
    |> assign(:counts, sidebar_counts(environments))
  end

  # Run a lifecycle action, then reload + flash. Any {:error, %Fuse.Error{}}
  # surfaces as a flash; we never crash the LiveView.
  defp run_action(socket, fun, success_message) do
    case fun.() do
      {:ok, _} ->
        socket |> reload() |> put_flash(:info, success_message)

      {:error, %Fuse.Error{} = error} ->
        put_flash(socket, :error, error.message)
    end
  end

  # Build the create-environment params from raw form input. Region (when
  # present) is merged into the plan's spec so fuse receives a single spec.
  defp create_environment(attrs) do
    task_id = attrs |> Map.get("task_id", "") |> String.trim()
    plan = Map.get(attrs, "plan", "")
    region = attrs |> Map.get("region", "") |> String.trim()
    overrides = if region == "", do: %{}, else: %{region: region}

    case Plan.spec(plan, overrides) do
      {:ok, spec} ->
        Environments.create(%{task_id: task_id, spec: spec})

      {:error, :unknown_plan} ->
        {:error, %Fuse.Error{code: "invalid_argument", message: "Unknown plan."}}

      {:error, _errors} ->
        {:error, %Fuse.Error{code: "invalid_argument", message: "Invalid plan options."}}
    end
  end

  defp create_form do
    to_form(%{"task_id" => "", "plan" => List.first(Plan.names()), "region" => ""}, as: :environment)
  end

  defp drainable?(state), do: state in @drainable

  defp sidebar_counts(environments) do
    %{
      environments: length(environments),
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

  defp filtered(environments, "all"), do: environments
  defp filtered(environments, state), do: Enum.filter(environments, &(&1.state == state))

  defp count_for(environments, state), do: Enum.count(environments, &(&1.state == state))

  # --- formatting ---

  defp spec_label(%Fuse.ResourceSpec{cpus: cpus, ram_mb: ram} = spec) do
    [cpu_part(cpus), ram_part(ram), region_part(spec.region)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
    |> case do
      "" -> "—"
      label -> label
    end
  end

  defp spec_label(_), do: "—"

  # Short "N vCPU · N GB" summary for a plan preset, shown in the select.
  defp plan_summary(plan) do
    case Plan.preset(plan) do
      %{cpus: cpus, ram_mb: ram} -> "#{cpu_part(cpus)} · #{ram_part(ram)}"
      _ -> ""
    end
  end

  defp cpu_part(nil), do: nil
  defp cpu_part(cpus), do: "#{cpus} vCPU"

  defp ram_part(nil), do: nil
  defp ram_part(ram_mb) when ram_mb >= 1024, do: "#{Float.round(ram_mb / 1024, 1) |> trim_float()} GB"
  defp ram_part(ram_mb), do: "#{ram_mb} MB"

  defp region_part(nil), do: nil
  defp region_part(""), do: nil
  defp region_part(region), do: region

  defp trim_float(float) do
    if float == trunc(float), do: trunc(float), else: float
  end

  defp label_for(nil), do: "Unknown"
  defp label_for(state), do: String.capitalize(state)

  defp dot_class("running"), do: "bg-ok"
  defp dot_class("provisioning"), do: "bg-warn"
  defp dot_class("draining"), do: "bg-warn"
  defp dot_class("destroying"), do: "bg-bad"
  defp dot_class("failed"), do: "bg-bad"
  defp dot_class(_), do: "bg-muted"

  # {dot, text, background}
  defp badge_classes("running"), do: {"bg-ok", "text-ok", "bg-ok-soft"}
  defp badge_classes("provisioning"), do: {"bg-warn", "text-warn", "bg-warn-soft"}
  defp badge_classes("draining"), do: {"bg-warn", "text-warn", "bg-warn-soft"}
  defp badge_classes("destroying"), do: {"bg-bad", "text-bad", "bg-bad-soft"}
  defp badge_classes("failed"), do: {"bg-bad", "text-bad", "bg-bad-soft"}
  defp badge_classes(_), do: {"bg-muted", "text-muted", "bg-surface-soft"}

  defp empty_message(_filter, %Fuse.Error{}), do: "No environments to show."
  defp empty_message("all", _), do: "No environments yet."
  defp empty_message(state, _), do: "No #{state} environments."
end
