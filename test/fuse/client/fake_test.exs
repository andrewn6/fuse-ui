defmodule Fuse.Client.FakeTest do
  use ExUnit.Case, async: true

  alias Fuse.Client.Fake
  alias Fuse.Error

  setup do
    {:ok, _pid} = Fake.start_link()
    :ok
  end

  describe "environments" do
    test "create then get" do
      assert {:ok, %{"id" => id, "state" => "provisioning", "task_id" => "t1"}} =
               Fake.create_environment(%{task_id: "t1", spec: %{cpus: 1}})

      assert {:ok, %{"id" => ^id}} = Fake.get_environment(id)
    end

    test "get unknown id returns a not_found error" do
      assert {:error, %Error{code: "not_found", status: 404}} = Fake.get_environment("nope")
    end

    test "drain transitions state to draining" do
      {:ok, env} = Fake.create_environment(%{task_id: "t1"})
      assert {:ok, %{"state" => "draining"}} = Fake.drain_environment(env["id"])
    end

    test "list filters by state" do
      {:ok, a} = Fake.create_environment(%{task_id: "t1"})
      {:ok, _b} = Fake.create_environment(%{task_id: "t2"})
      {:ok, _} = Fake.drain_environment(a["id"])

      assert {:ok, draining} = Fake.list_environments(%{state: "draining"})
      assert Enum.map(draining, & &1["id"]) == [a["id"]]

      assert {:ok, all} = Fake.list_environments(%{})
      assert length(all) == 2
    end

    test "rotate_token and destroy" do
      {:ok, env} = Fake.create_environment(%{task_id: "t1"})
      assert {:ok, nil} = Fake.rotate_token(env["id"])
      assert {:ok, nil} = Fake.destroy_environment(env["id"])
      assert {:error, %Error{code: "not_found"}} = Fake.get_environment(env["id"])
    end

    test "rotate_token on missing id errors" do
      assert {:error, %Error{code: "not_found"}} = Fake.rotate_token("nope")
    end
  end

  describe "seeding" do
    test "seeded environments (atom keys) are returned as string-keyed maps" do
      Fake.stop()
      {:ok, _} = Fake.start_link(environments: [%{id: "seed-1", state: "running", task_id: "t"}])

      assert {:ok, %{"id" => "seed-1", "state" => "running"}} = Fake.get_environment("seed-1")
      assert {:ok, [%{"id" => "seed-1"}]} = Fake.list_environments(%{})
    end
  end

  describe "snapshots" do
    test "create requires an existing vm, then list/get/restore/delete" do
      {:ok, env} = Fake.create_environment(%{task_id: "t1"})

      assert {:ok, snap} = Fake.create_snapshot(env["id"], %{comment: "nightly"})
      assert snap["vm_id"] == env["id"]
      assert snap["state"] == "creating"

      assert {:ok, [_]} = Fake.list_snapshots(%{vm_id: env["id"]})
      assert {:ok, %{"id" => snap_id}} = Fake.get_snapshot(snap["id"])
      assert {:ok, nil} = Fake.restore_snapshot(snap_id)
      assert {:ok, nil} = Fake.delete_snapshot(snap_id)
      assert {:error, %Error{code: "not_found"}} = Fake.get_snapshot(snap_id)
    end

    test "create on missing vm errors" do
      assert {:error, %Error{code: "not_found", message: "environment nope not found"}} =
               Fake.create_snapshot("nope", %{})
    end
  end

  describe "hosts" do
    test "register, list, cordon/uncordon, remove" do
      assert {:ok, host} =
               Fake.register_host(%{
                 id: "h1",
                 url: "http://h1",
                 capacity: %{cpus: 8, ram_mb: 16_000, storage_gb: 100, vm_count: 0}
               })

      assert host["state"] == "active"
      assert host["capacity"]["cpus"] == 8

      assert {:ok, [%{"id" => "h1"}]} = Fake.list_hosts()

      assert {:ok, nil} = Fake.cordon_host("h1")
      assert {:ok, %{"state" => "cordoned"}} = Fake.get_host("h1")

      assert {:ok, nil} = Fake.uncordon_host("h1")
      assert {:ok, %{"state" => "active"}} = Fake.get_host("h1")

      assert {:ok, nil} = Fake.remove_host("h1")
      assert {:error, %Error{code: "not_found"}} = Fake.get_host("h1")
    end
  end

  test "raises a helpful error if not started" do
    Fake.stop()
    assert_raise RuntimeError, ~r/not started/, fn -> Fake.get_environment("x") end
  end
end
