defmodule Fuse.Audit do
  @moduledoc """
  Append-only audit trail of mutating actions: who did what to which resource,
  when, and the outcome.

  `record/1` is called from the context layer (the single choke point every
  mutation flows through, whether it came from the dashboard or the REST API).
  It is **best-effort and gated**: a no-op when disabled
  (`config :fuse, Fuse.Audit, enabled: ...`), and a write that raises is
  swallowed — auditing must never break the action it records.

  ## Actor resolution

  The "who" is taken from `attrs.actor` if given, else from the calling process's
  `:audit_actor` dictionary entry, else `"system"`. The web layer stamps that
  entry once per request/mount: `FuseWeb.Plugs.AuditActor` sets `"api:<ip>"` for
  inbound API calls and `FuseWeb.AuthHook` sets `"console"` for the dashboard, so
  contexts don't need an actor threaded through every call.
  """

  require Logger
  import Ecto.Query

  alias Fuse.Audit.Action
  alias Fuse.Repo

  @pdict_actor :audit_actor

  @doc "Whether the audit log is turned on for this deployment."
  @spec enabled?() :: boolean()
  def enabled?, do: Application.get_env(:fuse, __MODULE__, [])[:enabled] == true

  @doc "Stamp the calling process's audit actor (used by the web layer)."
  @spec put_actor(String.t()) :: :ok
  def put_actor(actor) when is_binary(actor) do
    Process.put(@pdict_actor, actor)
    :ok
  end

  @doc """
  Record a mutating action. `attrs` needs `:action` and `:resource_type`;
  `:resource_id`, `:actor`, `:metadata`, `:result` are optional. Best-effort.
  """
  @spec record(map()) :: :ok
  def record(attrs) when is_map(attrs) do
    if enabled?(), do: insert(attrs), else: :ok
  end

  @doc """
  List audit entries, newest first. Filter by `:resource_type`, `:resource_id`,
  and cap with `:limit`. Returns `[]` when the log is disabled or unreadable.
  """
  @spec list(keyword()) :: [Action.t()]
  def list(opts \\ []) do
    if enabled?() do
      try do
        Action
        |> order_by([a], desc: a.occurred_at)
        |> maybe_filter(:resource_type, opts[:resource_type])
        |> maybe_filter(:resource_id, opts[:resource_id])
        |> maybe_limit(opts[:limit])
        |> Repo.all()
      rescue
        _ -> []
      catch
        :exit, _ -> []
      end
    else
      []
    end
  end

  # --- internals ---

  defp insert(attrs) do
    attrs =
      attrs
      |> Map.put_new(:occurred_at, DateTime.utc_now())
      |> Map.put_new(:result, "ok")
      |> Map.put(:actor, resolve_actor(attrs))

    %Action{}
    |> Action.changeset(attrs)
    |> Repo.insert()

    :ok
  rescue
    e -> log_skip(e)
  catch
    :exit, reason -> log_skip(reason)
  end

  defp resolve_actor(attrs) do
    attrs[:actor] || Process.get(@pdict_actor) || "system"
  end

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, field, value), do: where(query, [a], field(a, ^field) == ^value)

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, n), do: limit(query, ^n)

  defp log_skip(reason) do
    Logger.debug("audit write skipped: #{inspect(reason)}")
    :ok
  end
end
