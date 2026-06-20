defmodule Fuse.Mirror do
  @moduledoc """
  Local read-model cache of fuse environments and snapshots.

  fuse is always authoritative — this is a *cache* for audit, history, and
  offline inspection, populated two ways:

    * **write-through**: `Fuse.Environments`/`Fuse.Snapshots` upsert each row they
      decode from a fuse list/get response.
    * **events**: `Fuse.Mirror.Listener` patches an environment's live fields from
      the SSE stream (state/url/error) as events arrive.

  Every write is **best-effort and gated**: when the mirror is disabled (see
  `config :fuse, Fuse.Mirror, enabled: ...`) it is a no-op, and a write that
  raises (e.g. no DB connection in a sandboxed test, or a transient DB error in
  prod) is swallowed and logged at debug — it must never break the proxy request
  that triggered it.
  """

  require Logger
  import Ecto.Query

  alias Fuse.Environments.Environment, as: WireEnv
  alias Fuse.EventStream.Event
  alias Fuse.Mirror
  alias Fuse.Repo
  alias Fuse.Snapshots.Snapshot, as: WireSnap

  @doc "Whether the mirror is turned on for this deployment."
  @spec enabled?() :: boolean()
  def enabled?, do: Application.get_env(:fuse, __MODULE__, [])[:enabled] == true

  # --- write-through upserts ---

  @doc "Cache a decoded environment. Best-effort; returns `:ok` regardless."
  @spec upsert_environment(WireEnv.t()) :: :ok
  def upsert_environment(%WireEnv{id: id} = env) when is_binary(id) do
    guard(fn ->
      %Mirror.Environment{}
      |> Mirror.Environment.changeset(environment_attrs(env))
      |> Repo.insert(
        on_conflict: {:replace_all_except, [:id, :inserted_at]},
        conflict_target: :id
      )
    end)
  end

  def upsert_environment(_), do: :ok

  @doc "Cache a list of decoded environments. Best-effort."
  @spec upsert_environments([WireEnv.t()]) :: :ok
  def upsert_environments(envs) when is_list(envs) do
    Enum.each(envs, &upsert_environment/1)
  end

  @doc "Cache a decoded snapshot. Best-effort; returns `:ok` regardless."
  @spec upsert_snapshot(WireSnap.t()) :: :ok
  def upsert_snapshot(%WireSnap{id: id} = snap) when is_binary(id) do
    guard(fn ->
      %Mirror.Snapshot{}
      |> Mirror.Snapshot.changeset(snapshot_attrs(snap))
      |> Repo.insert(
        on_conflict: {:replace_all_except, [:id, :inserted_at]},
        conflict_target: :id
      )
    end)
  end

  def upsert_snapshot(_), do: :ok

  @doc "Cache a list of decoded snapshots. Best-effort."
  @spec upsert_snapshots([WireSnap.t()]) :: :ok
  def upsert_snapshots(snaps) when is_list(snaps) do
    Enum.each(snaps, &upsert_snapshot/1)
  end

  @doc """
  Patch a cached environment's live fields from an SSE event. Best-effort.

  Only the fields the event actually carries are written (a sparse event never
  blanks `task_id`/`host_id`/spec). If the env isn't cached yet, a thin row is
  inserted so the event isn't lost.
  """
  @spec apply_event(Event.t()) :: :ok
  def apply_event(%Event{vm_id: vm_id} = event) when is_binary(vm_id) do
    set =
      [
        state: event.state,
        url: event.url,
        error: event.error,
        fuse_updated_at: event.updated_at
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Keyword.put(:synced_at, now())

    insert = Map.merge(%{id: vm_id}, Map.new(set))

    guard(fn ->
      %Mirror.Environment{}
      |> Mirror.Environment.changeset(insert)
      |> Repo.insert(on_conflict: [set: set], conflict_target: :id)
    end)
  end

  def apply_event(_), do: :ok

  # --- reads (for audit UIs / tests; the app's hot path still reads from fuse) ---

  @doc "All cached environments, newest sync first."
  @spec list_environments() :: [Mirror.Environment.t()]
  def list_environments do
    safe_read(fn -> Repo.all(from e in Mirror.Environment, order_by: [desc: e.synced_at]) end, [])
  end

  @doc "A cached environment by id, or `nil`."
  @spec get_environment(String.t()) :: Mirror.Environment.t() | nil
  def get_environment(id), do: safe_read(fn -> Repo.get(Mirror.Environment, id) end, nil)

  @doc "All cached snapshots, newest sync first."
  @spec list_snapshots() :: [Mirror.Snapshot.t()]
  def list_snapshots do
    safe_read(fn -> Repo.all(from s in Mirror.Snapshot, order_by: [desc: s.synced_at]) end, [])
  end

  # --- internals ---

  defp environment_attrs(%WireEnv{} = env) do
    %{
      id: env.id,
      task_id: env.task_id,
      host_id: env.host_id,
      state: env.state,
      url: env.url,
      error: env.error,
      cpus: spec_field(env.spec, :cpus),
      ram_mb: spec_field(env.spec, :ram_mb),
      storage_gb: spec_field(env.spec, :storage_gb),
      region: spec_field(env.spec, :region),
      max_runtime_seconds: spec_field(env.spec, :max_runtime_seconds),
      fuse_created_at: env.created_at,
      fuse_updated_at: env.updated_at,
      synced_at: now()
    }
  end

  defp snapshot_attrs(%WireSnap{} = snap) do
    %{
      id: snap.id,
      vm_id: snap.vm_id,
      task_id: snap.task_id,
      tenant_id: snap.tenant_id,
      state: snap.state,
      mode: snap.mode,
      comment: snap.comment,
      size_bytes: snap.size_bytes,
      fuse_created_at: snap.created_at,
      synced_at: now()
    }
  end

  defp spec_field(nil, _key), do: nil
  defp spec_field(spec, key), do: Map.get(spec, key)

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  # run a write only when enabled, never letting it raise into the caller
  defp guard(fun) do
    if enabled?() do
      try do
        fun.()
        :ok
      rescue
        e -> log_skip(e)
      catch
        :exit, reason -> log_skip(reason)
      end
    else
      :ok
    end
  end

  defp safe_read(fun, default) do
    if enabled?() do
      try do
        fun.()
      rescue
        _ -> default
      catch
        :exit, _ -> default
      end
    else
      default
    end
  end

  defp log_skip(reason) do
    Logger.debug("mirror write skipped: #{inspect(reason)}")
    :ok
  end
end
