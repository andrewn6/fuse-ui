defmodule Fuse.EventStream do
  @moduledoc """
  Public API for watching fuse environment event streams.

  `watch/2` starts a supervised `Consumer` for an environment (idempotent per
  `vm_id`); the consumer broadcasts decoded events to `Phoenix.PubSub`.
  Subscribe with `subscribe/1` (one env) or `subscribe_all/0` (every watched
  env) and handle these messages:

      {:environment_event, %Fuse.EventStream.Event{}}
      {:environment_stream_down, vm_id, %Fuse.Error{}}

  *Who* calls `watch/unwatch` (e.g. a LiveView on mount, ref-counted) is a
  Phase 8 concern; this module only exposes the mechanism.
  """

  alias Fuse.EventStream.Consumer
  alias Fuse.EventStream.Supervisor, as: StreamSupervisor

  @registry Fuse.EventStream.Registry

  @doc "PubSub topic carrying events for every watched environment."
  @spec all_topic() :: String.t()
  def all_topic, do: "environments"

  @doc "PubSub topic carrying events for a single environment."
  @spec topic(String.t()) :: String.t()
  def topic(vm_id), do: "environment:#{vm_id}"

  @doc """
  Start watching `vm_id`'s event stream. Idempotent: a second call for an
  already-watched env returns the existing consumer.
  """
  @spec watch(String.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def watch(vm_id, opts \\ []) do
    child = {Consumer, Keyword.merge([vm_id: vm_id, name: via(vm_id)], opts)}

    case DynamicSupervisor.start_child(StreamSupervisor, child) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end

  @doc "Stop watching `vm_id`. Returns `:ok` whether or not it was watched."
  @spec unwatch(String.t()) :: :ok
  def unwatch(vm_id) do
    case whereis(vm_id) do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(StreamSupervisor, pid)
    end

    :ok
  end

  @doc "Whether an environment is currently being watched."
  @spec watching?(String.t()) :: boolean()
  def watching?(vm_id), do: whereis(vm_id) != nil

  @doc "The pid of the consumer watching `vm_id`, or `nil`."
  @spec whereis(String.t()) :: pid() | nil
  def whereis(vm_id) do
    # The Registry cleans up dead entries asynchronously (on its own monitor's
    # DOWN), so a just-terminated consumer can linger for an instant — filter it.
    case Registry.lookup(@registry, vm_id) do
      [{pid, _}] -> if Process.alive?(pid), do: pid, else: nil
      [] -> nil
    end
  end

  @doc "Subscribe the calling process to a single environment's events."
  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(vm_id), do: Phoenix.PubSub.subscribe(Fuse.PubSub, topic(vm_id))

  @doc "Subscribe the calling process to events for every watched environment."
  @spec subscribe_all() :: :ok | {:error, term()}
  def subscribe_all, do: Phoenix.PubSub.subscribe(Fuse.PubSub, all_topic())

  defp via(vm_id), do: {:via, Registry, {@registry, vm_id}}
end
