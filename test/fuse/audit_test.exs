defmodule Fuse.AuditTest do
  # async: false — toggles the global audit flag and stamps the process actor.
  use Fuse.DataCase, async: false

  alias Fuse.Audit
  alias Fuse.Environments

  setup do
    original = Application.get_env(:fuse, Audit)
    Application.put_env(:fuse, Audit, enabled: true)

    on_exit(fn ->
      Application.put_env(:fuse, Audit, original)
      Process.delete(:audit_actor)
    end)

    :ok
  end

  describe "record/1" do
    test "inserts an audit row with sensible defaults" do
      assert Audit.record(%{action: "create", resource_type: "environment", resource_id: "env-1"}) ==
               :ok

      assert [entry] = Audit.list()
      assert entry.action == "create"
      assert entry.resource_type == "environment"
      assert entry.resource_id == "env-1"
      assert entry.result == "ok"
      assert entry.actor == "system"
      assert %DateTime{} = entry.occurred_at
    end

    test "is a no-op when disabled" do
      Application.put_env(:fuse, Audit, enabled: false)
      assert Audit.record(%{action: "x", resource_type: "environment"}) == :ok
      assert Audit.list() == []
    end

    test "prefers an explicit actor over the process actor" do
      Audit.put_actor("console")

      Audit.record(%{
        action: "drain",
        resource_type: "environment",
        resource_id: "e",
        actor: "api:1.2.3.4"
      })

      assert [%{actor: "api:1.2.3.4"}] = Audit.list()
    end

    test "falls back to the process actor when none is given" do
      Audit.put_actor("console")
      Audit.record(%{action: "drain", resource_type: "environment", resource_id: "e"})
      assert [%{actor: "console"}] = Audit.list()
    end
  end

  describe "list/1" do
    test "filters by resource_type and resource_id" do
      Audit.record(%{action: "create", resource_type: "environment", resource_id: "e1"})
      Audit.record(%{action: "register", resource_type: "host", resource_id: "h1"})

      assert [%{resource_type: "host"}] = Audit.list(resource_type: "host")
      assert [%{resource_id: "e1"}] = Audit.list(resource_id: "e1")
      assert length(Audit.list()) == 2
      assert length(Audit.list(limit: 1)) == 1
    end
  end

  describe "recording through a context" do
    setup do
      {:ok, _} =
        Fuse.Client.Fake.start_link(
          environments: [%{id: "env-1", state: "running", task_id: "t"}]
        )

      :ok
    end

    test "a successful mutation records an entry" do
      assert {:ok, _} = Environments.drain("env-1")

      assert [entry] = Audit.list(resource_type: "environment")
      assert entry.action == "drain"
      assert entry.resource_id == "env-1"
    end

    test "a failed action records nothing" do
      assert {:error, _} = Environments.drain("missing")
      assert Audit.list() == []
    end
  end
end
