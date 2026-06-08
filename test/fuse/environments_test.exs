defmodule Fuse.EnvironmentsTest do
  # async: false — the create-request-body test swaps the global :fuse_client.
  use ExUnit.Case, async: false

  alias Fuse.Environments
  alias Fuse.Environments.Environment
  alias Fuse.Error
  alias Fuse.Manifest
  alias Fuse.ResourceSpec

  setup do
    {:ok, _} = Fuse.Client.Fake.start_link()
    :ok
  end

  defp valid_spec, do: %{cpus: 1, ram_mb: 512, storage_gb: 10}

  describe "create/1" do
    test "creates and decodes into an Environment struct" do
      assert {:ok, %Environment{} = env} =
               Environments.create(%{task_id: "t1", spec: %{cpus: 2, ram_mb: 2048, storage_gb: 20}})

      assert env.task_id == "t1"
      assert env.state == "provisioning"
      assert is_binary(env.id)
      assert %ResourceSpec{cpus: 2, ram_mb: 2048, storage_gb: 20} = env.spec
      assert %DateTime{} = env.created_at
    end

    test "accepts a %ResourceSpec{} directly" do
      spec = ResourceSpec.new!(valid_spec())

      assert {:ok, %Environment{spec: %ResourceSpec{cpus: 1}}} =
               Environments.create(%{task_id: "t1", spec: spec})
    end

    test "requires task_id" do
      assert {:error, %Error{code: "invalid_argument", message: "task_id is required"}} =
               Environments.create(%{spec: valid_spec()})
    end

    test "surfaces spec validation errors as invalid_argument" do
      assert {:error, %Error{code: "invalid_argument", message: "invalid spec", details: details}} =
               Environments.create(%{task_id: "t1", spec: %{ram_mb: 512}})

      assert details["cpus"] == "is required"
    end

    test "rejects a missing spec" do
      assert {:error, %Error{code: "invalid_argument", message: "spec is required"}} =
               Environments.create(%{task_id: "t1"})
    end

    test "builds the correct create request body (via HTTP stub)" do
      test_pid = self()

      with_http_client(fn conn ->
        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:body, Jason.decode!(raw)})

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(201, Jason.encode!(%{"id" => "env-1", "state" => "provisioning"}))
      end)

      assert {:ok, %Environment{id: "env-1"}} =
               Environments.create(%{
                 task_id: "t1",
                 spec: %{cpus: 2, ram_mb: 2048, storage_gb: 20, region: "us-east"},
                 manifest: %{"version" => "1"},
                 secrets: %{"API_KEY" => "x"},
                 startup_script: "echo hi",
                 gateway_url: "https://gw",
                 gateway_token: "gwtok"
               })

      assert_receive {:body, body}
      assert body["task_id"] == "t1"
      assert body["spec"] == %{"cpus" => 2, "ram_mb" => 2048, "storage_gb" => 20, "region" => "us-east"}
      assert body["secrets"] == %{"API_KEY" => "x"}
      assert body["startup_script"] == "echo hi"
      assert body["gateway_url"] == "https://gw"
      assert body["gateway_token"] == "gwtok"
      assert {:ok, %{"version" => "1"}} = Manifest.decode(body["manifest_inline"])
    end
  end

  describe "get/1 and list/1" do
    test "get decodes a struct; unknown id errors" do
      {:ok, env} = Environments.create(%{task_id: "t1", spec: valid_spec()})
      assert {:ok, %Environment{id: id}} = Environments.get(env.id)
      assert id == env.id
      assert {:error, %Error{code: "not_found"}} = Environments.get("nope")
    end

    test "list returns structs and filters by task_id" do
      {:ok, a} = Environments.create(%{task_id: "t1", spec: valid_spec()})
      {:ok, _b} = Environments.create(%{task_id: "t2", spec: valid_spec()})

      assert {:ok, envs} = Environments.list()
      assert length(envs) == 2
      assert Enum.all?(envs, &match?(%Environment{}, &1))

      assert {:ok, [only]} = Environments.list(%{task_id: "t1"})
      assert only.id == a.id
    end

    test "list is empty when there are no environments" do
      assert {:ok, []} = Environments.list()
    end
  end

  describe "lifecycle actions" do
    test "drain transitions state and decodes the result" do
      {:ok, env} = Environments.create(%{task_id: "t1", spec: valid_spec()})
      assert {:ok, %Environment{state: "draining"}} = Environments.drain(env.id)
    end

    test "rotate_token returns {:ok, nil}" do
      {:ok, env} = Environments.create(%{task_id: "t1", spec: valid_spec()})
      assert {:ok, nil} = Environments.rotate_token(env.id)
    end

    test "destroy removes the environment" do
      {:ok, env} = Environments.create(%{task_id: "t1", spec: valid_spec()})
      assert {:ok, nil} = Environments.destroy(env.id)
      assert {:error, %Error{code: "not_found"}} = Environments.get(env.id)
    end

    test "actions on unknown ids return not_found" do
      assert {:error, %Error{code: "not_found"}} = Environments.drain("nope")
      assert {:error, %Error{code: "not_found"}} = Environments.rotate_token("nope")
      assert {:error, %Error{code: "not_found"}} = Environments.destroy("nope")
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
