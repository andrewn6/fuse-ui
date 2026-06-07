defmodule Fuse.Client.Fake do
  @moduledoc """
  In-memory `Fuse.Client` implementation for tests.

  Backed by an `Agent` whose pid is stashed in the **calling process's**
  dictionary, so start it directly in your test setup (NOT via
  `start_supervised/1`, which would run in the supervisor process):

      setup do
        {:ok, _} = Fuse.Client.Fake.start_link()
        :ok
      end

  This is async-safe: each test process gets its own Agent. It relies on client
  calls happening synchronously in the test process (true for the context layer).

  Seed initial data with string- or atom-keyed maps:

      Fuse.Client.Fake.start_link(environments: [%{id: "env-1", state: "running", task_id: "t"}])

  Responses are string-keyed maps mirroring fuse's real JSON. Unknown ids yield
  a `not_found` `%Fuse.Error{}`.
  """

  @behaviour Fuse.Client

  alias Fuse.Error

  @pdict_key {__MODULE__, :agent}
  @fake_time "2026-01-01T00:00:00Z"

  @doc "Start the fake and register it in the calling process's dictionary."
  @spec start_link(keyword()) :: {:ok, pid()}
  def start_link(opts \\ []) do
    state = %{
      environments: index(opts[:environments] || []),
      snapshots: index(opts[:snapshots] || []),
      hosts: index(opts[:hosts] || []),
      seq: 0
    }

    {:ok, pid} = Agent.start_link(fn -> state end)
    Process.put(@pdict_key, pid)
    {:ok, pid}
  end

  @doc "Stop the fake and clear it from the process dictionary."
  @spec stop() :: :ok
  def stop do
    case Process.delete(@pdict_key) do
      nil -> :ok
      pid -> if Process.alive?(pid), do: Agent.stop(pid), else: :ok
    end
  end

  # --- Environments ---

  @impl true
  def list_environments(filters),
    do: {:ok, filter_by(all(:environments), filters, [:task_id, :state, :host_id])}

  @impl true
  def get_environment(id), do: fetch_one(:environments, id)

  @impl true
  def create_environment(params) do
    Agent.get_and_update(agent(), fn state ->
      seq = state.seq + 1
      id = "env-#{seq}"

      env = %{
        "id" => id,
        "state" => "provisioning",
        "task_id" => fetch(params, :task_id),
        "spec" => stringify(fetch(params, :spec) || %{}),
        "url" => "https://#{id}.fake.fuse.test",
        "created_at" => @fake_time,
        "updated_at" => @fake_time
      }

      {{:ok, env}, state |> put_in([:environments, id], env) |> Map.put(:seq, seq)}
    end)
  end

  @impl true
  def drain_environment(id), do: update_one(:environments, id, &Map.put(&1, "state", "draining"))

  @impl true
  def rotate_token(id), do: ack_if_present(:environments, id)

  @impl true
  def destroy_environment(id), do: delete_one(:environments, id)

  # --- Snapshots ---

  @impl true
  def create_snapshot(vm_id, params) do
    Agent.get_and_update(agent(), fn state ->
      if Map.has_key?(state.environments, vm_id) do
        seq = state.seq + 1
        id = "snap-#{seq}"

        snap = %{
          "id" => id,
          "vm_id" => vm_id,
          "state" => "creating",
          "comment" => fetch(params, :comment),
          "mode" => fetch(params, :mode),
          "exports" => [],
          "created_at" => @fake_time,
          "updated_at" => @fake_time
        }

        {{:ok, snap}, state |> put_in([:snapshots, id], snap) |> Map.put(:seq, seq)}
      else
        {not_found(:environments, vm_id), state}
      end
    end)
  end

  @impl true
  def list_snapshots(filters),
    do: {:ok, filter_by(all(:snapshots), filters, [:vm_id, :task_id, :tenant_id, :state])}

  @impl true
  def get_snapshot(id), do: fetch_one(:snapshots, id)

  @impl true
  def restore_snapshot(id), do: ack_if_present(:snapshots, id)

  @impl true
  def delete_snapshot(id), do: delete_one(:snapshots, id)

  # --- Hosts ---

  @impl true
  def register_host(params) do
    id = fetch(params, :id)

    host = %{
      "id" => id,
      "url" => fetch(params, :url),
      "region" => fetch(params, :region),
      "state" => "active",
      "capacity" => stringify(fetch(params, :capacity) || %{}),
      "allocated" => %{"cpus" => 0, "ram_mb" => 0, "storage_gb" => 0, "vm_count" => 0},
      "last_seen" => @fake_time,
      "created_at" => @fake_time,
      "updated_at" => @fake_time
    }

    Agent.update(agent(), &put_in(&1, [:hosts, id], host))
    {:ok, host}
  end

  @impl true
  def list_hosts, do: {:ok, all(:hosts)}

  @impl true
  def get_host(id), do: fetch_one(:hosts, id)

  @impl true
  def cordon_host(id), do: set_host_state(id, "cordoned")

  @impl true
  def uncordon_host(id), do: set_host_state(id, "active")

  @impl true
  def remove_host(id), do: delete_one(:hosts, id)

  # --- internals ---

  defp agent do
    Process.get(@pdict_key) ||
      raise "Fuse.Client.Fake not started — call Fuse.Client.Fake.start_link/1 in your test setup"
  end

  defp all(collection), do: Agent.get(agent(), fn s -> Map.values(s[collection]) end)

  defp fetch_one(collection, id) do
    case Agent.get(agent(), fn s -> Map.get(s[collection], id) end) do
      nil -> not_found(collection, id)
      item -> {:ok, item}
    end
  end

  defp update_one(collection, id, fun) do
    Agent.get_and_update(agent(), fn s ->
      case Map.get(s[collection], id) do
        nil ->
          {not_found(collection, id), s}

        item ->
          updated = fun.(item) |> Map.put("updated_at", @fake_time)
          {{:ok, updated}, put_in(s, [collection, id], updated)}
      end
    end)
  end

  defp delete_one(collection, id) do
    Agent.get_and_update(agent(), fn s ->
      case Map.get(s[collection], id) do
        nil -> {not_found(collection, id), s}
        _ -> {{:ok, nil}, update_in(s, [collection], &Map.delete(&1, id))}
      end
    end)
  end

  # Verify the resource exists, then mimic a 204 (no body) action response.
  defp ack_if_present(collection, id) do
    with {:ok, _} <- fetch_one(collection, id), do: {:ok, nil}
  end

  defp set_host_state(id, state) do
    case update_one(:hosts, id, &Map.put(&1, "state", state)) do
      {:ok, _} -> {:ok, nil}
      error -> error
    end
  end

  defp filter_by(items, filters, keys) do
    Enum.reduce(keys, items, fn key, acc ->
      case fetch(filters, key) do
        nil ->
          acc

        value ->
          string_key = Atom.to_string(key)
          Enum.filter(acc, fn item -> to_string(Map.get(item, string_key)) == to_string(value) end)
      end
    end)
  end

  defp not_found(collection, id) do
    {:error,
     %Error{code: "not_found", message: "#{label(collection)} #{id} not found", status: 404}}
  end

  defp label(:environments), do: "environment"
  defp label(:snapshots), do: "snapshot"
  defp label(:hosts), do: "host"

  defp index(list), do: Map.new(list, fn item -> s = stringify(item); {s["id"], s} end)

  defp fetch(map, key) when is_atom(key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp stringify(map) when is_map(map) and not is_struct(map),
    do: Map.new(map, fn {k, v} -> {to_string(k), stringify(v)} end)

  defp stringify(list) when is_list(list), do: Enum.map(list, &stringify/1)
  defp stringify(other), do: other
end
