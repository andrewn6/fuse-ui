defmodule Fuse.Client.HTTPTest do
  # async: false — these tests mutate the global Fuse.Client.HTTP app config.
  use ExUnit.Case, async: false

  alias Fuse.Client.HTTP
  alias Fuse.Error

  setup do
    previous = Application.get_env(:fuse, HTTP)
    on_exit(fn -> Application.put_env(:fuse, HTTP, previous) end)
    :ok
  end

  # Install a Req plug stub for the duration of one test.
  defp stub(fun) do
    Application.put_env(:fuse, HTTP,
      base_url: "http://fuse.test",
      token: "secret-token",
      req_options: [retry: false, plug: fun]
    )
  end

  defp json(conn, status, data) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(data))
  end

  test "get_environment/1 returns the decoded body on 200" do
    stub(fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/v1/environments/env-1"
      json(conn, 200, %{"id" => "env-1", "state" => "running"})
    end)

    assert {:ok, %{"id" => "env-1", "state" => "running"}} = HTTP.get_environment("env-1")
  end

  test "sends the bearer token and a generated X-Request-ID header" do
    stub(fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer secret-token"]
      assert [request_id] = Plug.Conn.get_req_header(conn, "x-request-id")
      assert request_id =~ ~r/^req_[0-9a-f]{32}$/
      json(conn, 200, %{"id" => "env-1"})
    end)

    assert {:ok, _} = HTTP.get_environment("env-1")
  end

  test "list_environments/1 unwraps the envelope and forwards filters as query params" do
    stub(fn conn ->
      assert conn.request_path == "/v1/environments"
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.query_params["state"] == "running"
      assert conn.query_params["task_id"] == "t1"
      json(conn, 200, %{"environments" => [%{"id" => "env-1"}, %{"id" => "env-2"}]})
    end)

    assert {:ok, [%{"id" => "env-1"}, %{"id" => "env-2"}]} =
             HTTP.list_environments(%{state: "running", task_id: "t1"})
  end

  test "list_environments/1 returns [] when the envelope key is absent" do
    stub(fn conn -> json(conn, 200, %{}) end)
    assert {:ok, []} = HTTP.list_environments(%{})
  end

  test "create_environment/1 posts the JSON body and returns the created object" do
    stub(fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v1/environments"
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      assert Jason.decode!(raw)["task_id"] == "t1"
      json(conn, 201, %{"id" => "env-9", "state" => "provisioning"})
    end)

    assert {:ok, %{"id" => "env-9", "state" => "provisioning"}} =
             HTTP.create_environment(%{task_id: "t1", spec: %{cpus: 1}})
  end

  test "drain_environment/1 sends ?action=drain and returns the updated env" do
    stub(fn conn ->
      assert conn.method == "POST"
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.query_params["action"] == "drain"
      json(conn, 200, %{"id" => "env-1", "state" => "draining"})
    end)

    assert {:ok, %{"state" => "draining"}} = HTTP.drain_environment("env-1")
  end

  test "rotate_token/1 returns {:ok, nil} on 204" do
    stub(fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.query_params["action"] == "rotate-token"
      Plug.Conn.send_resp(conn, 204, "")
    end)

    assert {:ok, nil} = HTTP.rotate_token("env-1")
  end

  test "destroy_environment/1 returns {:ok, nil} on 204" do
    stub(fn conn ->
      assert conn.method == "DELETE"
      Plug.Conn.send_resp(conn, 204, "")
    end)

    assert {:ok, nil} = HTTP.destroy_environment("env-1")
  end

  test "maps a non-2xx error envelope to %Fuse.Error{}" do
    stub(fn conn ->
      json(conn, 404, %{"error" => %{"code" => "not_found", "message" => "vm x not found"}})
    end)

    assert {:error, %Error{code: "not_found", message: "vm x not found", status: 404}} =
             HTTP.get_environment("x")
  end

  test "maps a transport failure to a transport %Fuse.Error{}" do
    stub(fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

    assert {:error, %Error{code: "transport_error", status: nil}} = HTTP.get_environment("x")
  end

  test "host and snapshot helpers hit the right paths" do
    stub(fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/v1/hosts"} -> json(conn, 200, %{"hosts" => [%{"id" => "h1"}]})
        {"POST", "/v1/snapshots/snap-1"} -> Plug.Conn.send_resp(conn, 204, "")
        other -> flunk("unexpected request: #{inspect(other)}")
      end
    end)

    assert {:ok, [%{"id" => "h1"}]} = HTTP.list_hosts()
    assert {:ok, nil} = HTTP.restore_snapshot("snap-1")
  end
end
