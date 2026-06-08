defmodule Fuse.SnapshotsTest do
  # async: false — the create-request-body test swaps the global :fuse_client.
  use ExUnit.Case, async: false

  alias Fuse.Error
  alias Fuse.Snapshots
  alias Fuse.Snapshots.Snapshot

  setup do
    # Seed an environment so snapshot creation has a vm to target.
    {:ok, _} = Fuse.Client.Fake.start_link(environments: [%{id: "vm-1", state: "running", task_id: "t"}])
    :ok
  end

  describe "create/2" do
    test "creates and decodes into a Snapshot struct" do
      assert {:ok, %Snapshot{} = snap} = Snapshots.create("vm-1", %{comment: "nightly", mode: "full"})
      assert snap.vm_id == "vm-1"
      assert snap.state == "creating"
      assert snap.comment == "nightly"
      assert is_binary(snap.id)
      assert snap.exports == []
    end

    test "create on a missing vm returns not_found" do
      assert {:error, %Error{code: "not_found"}} = Snapshots.create("nope")
    end

    test "requires a vm_id" do
      assert {:error, %Error{code: "invalid_argument", message: "vm_id is required"}} =
               Snapshots.create(nil)
    end

    test "builds the correct create request body (via HTTP stub)" do
      test_pid = self()

      with_http_client(fn conn ->
        assert conn.request_path == "/v1/environments/vm-1/snapshots"
        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:body, Jason.decode!(raw)})

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(201, Jason.encode!(%{"id" => "snap-1", "vm_id" => "vm-1", "state" => "creating"}))
      end)

      assert {:ok, %Snapshot{id: "snap-1"}} =
               Snapshots.create("vm-1", %{
                 comment: "c",
                 mode: "full",
                 retention_seconds: 3600,
                 metadata: %{"team" => "core"},
                 export_ref: "s3://bucket/key",
                 export_status: "pending"
               })

      assert_receive {:body, body}
      assert body == %{
               "comment" => "c",
               "mode" => "full",
               "retention_seconds" => 3600,
               "metadata" => %{"team" => "core"},
               "export_ref" => "s3://bucket/key",
               "export_status" => "pending"
             }
    end
  end

  describe "get/1 and list/1" do
    test "get decodes a struct; unknown id errors" do
      {:ok, snap} = Snapshots.create("vm-1", %{comment: "c"})
      assert {:ok, %Snapshot{id: id}} = Snapshots.get(snap.id)
      assert id == snap.id
      assert {:error, %Error{code: "not_found"}} = Snapshots.get("nope")
    end

    test "list returns structs and filters by vm_id" do
      {:ok, _a} = Snapshots.create("vm-1", %{comment: "a"})
      {:ok, _b} = Snapshots.create("vm-1", %{comment: "b"})

      assert {:ok, snaps} = Snapshots.list()
      assert length(snaps) == 2
      assert Enum.all?(snaps, &match?(%Snapshot{}, &1))

      assert {:ok, only} = Snapshots.list(%{vm_id: "vm-1"})
      assert length(only) == 2
      assert {:ok, []} = Snapshots.list(%{vm_id: "other"})
    end
  end

  describe "decoding" do
    test "decodes nested exports and retention_until into structs/DateTime" do
      Fuse.Client.Fake.stop()

      {:ok, _} =
        Fuse.Client.Fake.start_link(
          snapshots: [
            %{
              id: "snap-9",
              vm_id: "vm-1",
              state: "ready",
              retention_until: "2026-02-01T00:00:00Z",
              exports: [%{destination: "s3://b/k", status: "ready"}]
            }
          ]
        )

      assert {:ok, %Snapshot{} = snap} = Snapshots.get("snap-9")
      assert Snapshot.ready?(snap)
      assert %DateTime{} = snap.retention_until
      assert [%Snapshot.Export{destination: "s3://b/k", status: "ready"}] = snap.exports
    end
  end

  describe "restore/1 and delete/1" do
    test "restore returns {:ok, nil}; unknown id errors" do
      {:ok, snap} = Snapshots.create("vm-1", %{comment: "c"})
      assert {:ok, nil} = Snapshots.restore(snap.id)
      assert {:error, %Error{code: "not_found"}} = Snapshots.restore("nope")
    end

    test "delete removes the snapshot" do
      {:ok, snap} = Snapshots.create("vm-1", %{comment: "c"})
      assert {:ok, nil} = Snapshots.delete(snap.id)
      assert {:error, %Error{code: "not_found"}} = Snapshots.get(snap.id)
    end
  end

  # Temporarily route Fuse.Client through the HTTP impl with a plug stub.
  defp with_http_client(plug) do
    previous_impl = Application.get_env(:fuse, :fuse_client)
    previous_http = Application.get_env(:fuse, Fuse.Client.HTTP)

    Application.put_env(:fuse, :fuse_client, Fuse.Client.HTTP)

    Application.put_env(:fuse, Fuse.Client.HTTP,
      base_url: "http://fuse.test",
      token: "secret",
      req_options: [retry: false, plug: plug]
    )

    on_exit(fn ->
      Application.put_env(:fuse, :fuse_client, previous_impl)
      Application.put_env(:fuse, Fuse.Client.HTTP, previous_http)
    end)
  end
end
