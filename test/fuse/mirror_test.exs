defmodule Fuse.MirrorTest do
  # async: false — toggles the global mirror flag and uses the shared sandbox.
  use Fuse.DataCase, async: false

  alias Fuse.Environments
  alias Fuse.Environments.Environment, as: WireEnv
  alias Fuse.EventStream.Event
  alias Fuse.Mirror
  alias Fuse.ResourceSpec
  alias Fuse.Snapshots

  setup do
    original = Application.get_env(:fuse, Mirror)
    Application.put_env(:fuse, Mirror, enabled: true)
    on_exit(fn -> Application.put_env(:fuse, Mirror, original) end)
    {:ok, _} = Fuse.Client.Fake.start_link()
    :ok
  end

  defp wire_env(attrs) do
    %WireEnv{
      id: attrs[:id] || "env_1",
      task_id: Map.get(attrs, :task_id, "task_a"),
      host_id: Map.get(attrs, :host_id, "host_x"),
      state: attrs[:state] || "running",
      url: attrs[:url],
      error: attrs[:error],
      spec: ResourceSpec.new!(%{cpus: 2, ram_mb: 2048, storage_gb: 20}),
      created_at: ~U[2026-06-01 00:00:00Z],
      updated_at: ~U[2026-06-01 00:00:00Z]
    }
  end

  describe "upsert_environment/1" do
    test "inserts a cache row from a decoded environment" do
      assert Mirror.upsert_environment(wire_env(%{id: "env_a"})) == :ok

      row = Mirror.get_environment("env_a")
      assert row.task_id == "task_a"
      assert row.host_id == "host_x"
      assert row.state == "running"
      assert row.cpus == 2
      assert row.ram_mb == 2048
      assert row.storage_gb == 20
      assert %DateTime{} = row.synced_at
    end

    test "updates the existing row on re-upsert (id is the conflict key)" do
      Mirror.upsert_environment(wire_env(%{id: "env_b", state: "provisioning"}))
      Mirror.upsert_environment(wire_env(%{id: "env_b", state: "running", url: "https://b"}))

      row = Mirror.get_environment("env_b")
      assert row.state == "running"
      assert row.url == "https://b"
      assert Enum.count(Mirror.list_environments(), &(&1.id == "env_b")) == 1
    end

    test "is a no-op when the mirror is disabled" do
      Application.put_env(:fuse, Mirror, enabled: false)
      assert Mirror.upsert_environment(wire_env(%{id: "env_off"})) == :ok
      # a disabled read returns the empty default, so nothing leaks either way
      assert Mirror.get_environment("env_off") == nil
    end
  end

  describe "apply_event/1" do
    test "patches live fields without blanking spec/task" do
      Mirror.upsert_environment(wire_env(%{id: "env_c", state: "provisioning"}))

      event = %Event{
        vm_id: "env_c",
        state: "running",
        url: "https://c",
        updated_at: ~U[2026-06-02 00:00:00Z]
      }

      assert Mirror.apply_event(event) == :ok

      row = Mirror.get_environment("env_c")
      assert row.state == "running"
      assert row.url == "https://c"
      assert row.task_id == "task_a"
      assert row.cpus == 2
    end

    test "a sparse event never blanks an existing url" do
      Mirror.upsert_environment(wire_env(%{id: "env_d", state: "running", url: "https://d"}))
      assert Mirror.apply_event(%Event{vm_id: "env_d", state: "draining"}) == :ok

      row = Mirror.get_environment("env_d")
      assert row.state == "draining"
      assert row.url == "https://d"
    end

    test "inserts a thin row for an unknown env" do
      assert Mirror.apply_event(%Event{vm_id: "env_new", state: "running"}) == :ok

      row = Mirror.get_environment("env_new")
      assert row.state == "running"
      assert row.task_id == nil
    end
  end

  describe "write-through from contexts" do
    test "Environments.get caches the fetched environment" do
      :ok = Fuse.Client.Fake.stop()

      {:ok, _} =
        Fuse.Client.Fake.start_link(
          environments: [
            %{id: "env-seed", state: "running", task_id: "t", host_id: "h"}
          ]
        )

      assert {:ok, _} = Environments.get("env-seed")

      assert %{id: "env-seed", state: "running"} =
               Map.take(Mirror.get_environment("env-seed"), [:id, :state])
    end

    test "Snapshots.list caches each snapshot" do
      :ok = Fuse.Client.Fake.stop()

      {:ok, _} =
        Fuse.Client.Fake.start_link(snapshots: [%{id: "snap-seed", vm_id: "vm1", state: "ready"}])

      assert {:ok, _} = Snapshots.list()
      assert Mirror.list_snapshots() |> Enum.any?(&(&1.id == "snap-seed"))
    end
  end
end
