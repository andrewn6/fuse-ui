defmodule Fuse.Integration.FuseRoundTripTest do
  @moduledoc """
  End-to-end lifecycle round trip against a REAL fuse instance.

  Excluded from the normal suite (tagged `:integration`). Run it against a live
  fuse with:

      FUSE_BASE_URL=http://localhost:8080 FUSE_TOKEN=... mix test --include integration

  It drives the full lifecycle through the real HTTP client —
  create -> snapshot -> restore -> drain -> destroy — asserting the state at each
  step and always cleaning up the environment it created.
  """

  use ExUnit.Case, async: false

  @moduletag :integration
  # generous: real provisioning + snapshot/restore take real time
  @moduletag timeout: 300_000

  alias Fuse.Environments
  alias Fuse.Snapshots

  setup_all do
    base_url =
      System.get_env("FUSE_BASE_URL") ||
        flunk("set FUSE_BASE_URL (and usually FUSE_TOKEN) to run integration tests")

    # point the dispatcher at the real HTTP client for this run
    prev_client = Application.get_env(:fuse, :fuse_client)
    prev_http = Application.get_env(:fuse, Fuse.Client.HTTP)

    Application.put_env(:fuse, :fuse_client, Fuse.Client.HTTP)

    Application.put_env(:fuse, Fuse.Client.HTTP,
      base_url: base_url,
      token: System.get_env("FUSE_TOKEN")
    )

    on_exit(fn ->
      Application.put_env(:fuse, :fuse_client, prev_client)
      Application.put_env(:fuse, Fuse.Client.HTTP, prev_http)
    end)

    :ok
  end

  test "create -> snapshot -> restore -> drain -> destroy" do
    task_id = "integration-#{System.unique_integer([:positive])}"

    assert {:ok, env} =
             Environments.create(%{
               task_id: task_id,
               spec: %{cpus: 1, ram_mb: 512, storage_gb: 10}
             })

    on_exit(fn -> Environments.destroy(env.id) end)
    assert env.state in ~w(provisioning running)

    # wait for it to be running before snapshotting
    assert {:ok, running} = wait_for_state(env.id, "running")
    assert running.state == "running"

    assert {:ok, snap} = Snapshots.create(env.id, %{comment: "round-trip"})
    assert {:ok, _ready_snap} = wait_for_snapshot(snap.id, "ready")

    assert {:ok, _} = Snapshots.restore(snap.id)

    assert {:ok, _} = Environments.drain(env.id)
    assert {:ok, _} = Environments.destroy(env.id)

    # destroyed envs eventually 404
    assert {:error, %Fuse.Error{}} = wait_until_gone(env.id)
  end

  # --- polling helpers ---

  defp wait_for_state(id, target), do: poll(fn -> env_in_state(id, target) end)

  defp env_in_state(id, target) do
    case Environments.get(id) do
      {:ok, %{state: ^target} = env} -> {:ok, env}
      {:ok, %{state: "failed"} = env} -> {:halt, {:error, {:failed, env}}}
      other -> {:retry, other}
    end
  end

  defp wait_for_snapshot(id, target) do
    poll(fn ->
      case Snapshots.get(id) do
        {:ok, %{state: ^target} = snap} -> {:ok, snap}
        {:ok, %{state: "error"} = snap} -> {:halt, {:error, {:snapshot_error, snap}}}
        other -> {:retry, other}
      end
    end)
  end

  defp wait_until_gone(id) do
    poll(fn ->
      case Environments.get(id) do
        {:error, _} = err -> {:ok, err}
        other -> {:retry, other}
      end
    end)
    |> case do
      {:ok, err} -> err
      other -> other
    end
  end

  # poll `fun` (returns {:ok, _} done, {:retry, _} keep going, {:halt, _} fail
  # fast) up to ~60s
  defp poll(fun, attempts \\ 120, interval \\ 500)

  defp poll(_fun, 0, _interval), do: {:error, :timeout}

  defp poll(fun, attempts, interval) do
    case fun.() do
      {:ok, _} = ok ->
        ok

      {:halt, result} ->
        result

      {:retry, _} ->
        Process.sleep(interval)
        poll(fun, attempts - 1, interval)
    end
  end
end
