defmodule Fuse.HostsTest do
  # async: false — the register-request-body test swaps the global :fuse_client.
  use ExUnit.Case, async: false

  alias Fuse.Error
  alias Fuse.Hosts
  alias Fuse.Hosts.Host

  setup do
    {:ok, _} = Fuse.Client.Fake.start_link()
    :ok
  end

  defp capacity, do: %{cpus: 8, ram_mb: 16_000, storage_gb: 100, vm_count: 0}

  defp valid_attrs, do: %{id: "host-1", url: "https://host-1.fuse.test", capacity: capacity()}

  describe "register/1" do
    test "registers and decodes into a Host struct" do
      assert {:ok, %Host{} = host} = Hosts.register(valid_attrs())
      assert host.id == "host-1"
      assert host.url == "https://host-1.fuse.test"
      assert host.state == "active"
      assert %Host.Capacity{cpus: 8, ram_mb: 16_000, storage_gb: 100, vm_count: 0} = host.capacity
      assert %Host.Capacity{cpus: 0} = host.allocated
      assert %DateTime{} = host.created_at
    end

    test "requires id, url, and capacity" do
      assert {:error, %Error{code: "invalid_argument", message: "id is required"}} =
               Hosts.register(%{url: "u", capacity: capacity()})

      assert {:error, %Error{code: "invalid_argument", message: "url is required"}} =
               Hosts.register(%{id: "h", capacity: capacity()})

      assert {:error, %Error{code: "invalid_argument", message: "capacity is required"}} =
               Hosts.register(%{id: "h", url: "u"})
    end

    test "builds the correct register request body (via HTTP stub)" do
      test_pid = self()

      with_http_client(fn conn ->
        assert conn.request_path == "/v1/hosts"
        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:body, Jason.decode!(raw)})

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(201, Jason.encode!(%{"id" => "host-1", "state" => "active"}))
      end)

      assert {:ok, %Host{id: "host-1"}} =
               Hosts.register(%{
                 id: "host-1",
                 url: "https://host-1.fuse.test",
                 region: "us-east",
                 token: "host-token",
                 capacity: capacity()
               })

      assert_receive {:body, body}

      assert body == %{
               "id" => "host-1",
               "url" => "https://host-1.fuse.test",
               "region" => "us-east",
               "token" => "host-token",
               "capacity" => %{
                 "cpus" => 8,
                 "ram_mb" => 16_000,
                 "storage_gb" => 100,
                 "vm_count" => 0
               }
             }
    end

    test "omits optional token/region when not given" do
      test_pid = self()

      with_http_client(fn conn ->
        {:ok, raw, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:body, Jason.decode!(raw)})

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(201, Jason.encode!(%{"id" => "host-1", "state" => "active"}))
      end)

      assert {:ok, %Host{}} = Hosts.register(valid_attrs())

      assert_receive {:body, body}
      refute Map.has_key?(body, "token")
      refute Map.has_key?(body, "region")
    end
  end

  describe "get/1 and list/0" do
    test "get decodes a struct; unknown id errors" do
      {:ok, host} = Hosts.register(valid_attrs())
      assert {:ok, %Host{id: id}} = Hosts.get(host.id)
      assert id == host.id
      assert {:error, %Error{code: "not_found"}} = Hosts.get("nope")
    end

    test "list returns structs" do
      {:ok, _} = Hosts.register(valid_attrs())
      {:ok, _} = Hosts.register(%{valid_attrs() | id: "host-2", url: "https://host-2.fuse.test"})

      assert {:ok, hosts} = Hosts.list()
      assert length(hosts) == 2
      assert Enum.all?(hosts, &match?(%Host{}, &1))
    end

    test "list is empty when there are no hosts" do
      assert {:ok, []} = Hosts.list()
    end
  end

  describe "cordon/uncordon/remove" do
    test "cordon then uncordon flips state" do
      {:ok, host} = Hosts.register(valid_attrs())

      assert {:ok, nil} = Hosts.cordon(host.id)
      assert {:ok, %Host{state: "cordoned"}} = Hosts.get(host.id)

      assert {:ok, nil} = Hosts.uncordon(host.id)
      assert {:ok, %Host{state: "active"}} = Hosts.get(host.id)
    end

    test "remove deletes the host" do
      {:ok, host} = Hosts.register(valid_attrs())
      assert {:ok, nil} = Hosts.remove(host.id)
      assert {:error, %Error{code: "not_found"}} = Hosts.get(host.id)
    end

    test "actions on unknown ids return not_found" do
      assert {:error, %Error{code: "not_found"}} = Hosts.cordon("nope")
      assert {:error, %Error{code: "not_found"}} = Hosts.uncordon("nope")
      assert {:error, %Error{code: "not_found"}} = Hosts.remove("nope")
    end
  end

  describe "decoding" do
    test "decodes capacity/allocated and timestamps" do
      Fuse.Client.Fake.stop()

      {:ok, _} =
        Fuse.Client.Fake.start_link(
          hosts: [
            %{
              id: "host-9",
              url: "https://host-9.fuse.test",
              region: "eu-west",
              state: "draining",
              capacity: %{cpus: 16, ram_mb: 32_000, storage_gb: 500, vm_count: 4},
              allocated: %{cpus: 4, ram_mb: 8_000, storage_gb: 100, vm_count: 2},
              last_seen: "2026-02-01T00:00:00Z",
              created_at: "2026-01-01T00:00:00Z",
              updated_at: "2026-02-01T00:00:00Z"
            }
          ]
        )

      assert {:ok, %Host{} = host} = Hosts.get("host-9")
      assert Host.draining?(host)
      assert %Host.Capacity{cpus: 16, vm_count: 4} = host.capacity
      assert %Host.Capacity{cpus: 4, vm_count: 2} = host.allocated
      assert %DateTime{} = host.last_seen
      assert %DateTime{} = host.created_at
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
