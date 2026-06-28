defmodule FuseWeb.AuthGateTest do
  # async: false — toggles the global console-auth + fuse-client config.
  use FuseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @host %{
    "id" => "host_1",
    "url" => "https://host-1.internal:8443",
    "region" => "us-east-1",
    "state" => "active",
    "capacity" => %{"cpus" => 16, "ram_mb" => 32_768, "storage_gb" => 500, "vm_count" => 48},
    "allocated" => %{"cpus" => 0, "ram_mb" => 0, "storage_gb" => 0, "vm_count" => 0},
    "last_seen" => "2026-06-01T12:00:00Z",
    "created_at" => "2026-06-01T00:00:00Z",
    "updated_at" => "2026-06-01T12:00:00Z"
  }

  setup do
    prev_auth = Application.get_env(:fuse, FuseWeb.Auth)
    prev_client = Application.get_env(:fuse, :fuse_client)
    prev_http = Application.get_env(:fuse, Fuse.Client.HTTP)

    Application.put_env(:fuse, FuseWeb.Auth, enforce: true)
    Application.put_env(:fuse, :fuse_client, Fuse.Client.HTTP)

    on_exit(fn ->
      Application.put_env(:fuse, FuseWeb.Auth, prev_auth)
      Application.put_env(:fuse, :fuse_client, prev_client)
      Application.put_env(:fuse, Fuse.Client.HTTP, prev_http)
    end)

    :ok
  end

  defp put_plug(plug) do
    Application.put_env(:fuse, Fuse.Client.HTTP,
      base_url: "http://fuse.test",
      token: "t",
      req_options: [retry: false, plug: plug]
    )
  end

  defp json(conn, status \\ 200, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  def stub_with_hosts(conn) do
    case {conn.method, conn.request_path} do
      {"GET", "/v1/hosts"} -> json(conn, %{"hosts" => [@host]})
      {"GET", "/ready"} -> json(conn, %{"status" => "ok"})
      _ -> json(conn, %{"environments" => [], "snapshots" => []})
    end
  end

  def stub_no_hosts(conn) do
    case {conn.method, conn.request_path} do
      {"GET", "/v1/hosts"} -> json(conn, %{"hosts" => []})
      {"GET", "/ready"} -> json(conn, %{"status" => "ok"})
      _ -> json(conn, %{"environments" => [], "snapshots" => []})
    end
  end

  test "an unconfigured console redirects the console to /setup", %{conn: conn} do
    assert redirected_to(get(conn, ~p"/environments")) == ~p"/setup"
  end

  test "configured but unauthenticated is redirected to /login", %{conn: conn} do
    configure_admin()
    put_plug(&__MODULE__.stub_with_hosts/1)

    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/environments")
  end

  test "authenticated with no hosts is funnelled to /onboarding", %{conn: conn} do
    configure_admin()
    put_plug(&__MODULE__.stub_no_hosts/1)

    assert {:error, {:redirect, %{to: "/onboarding"}}} = live(log_in(conn), ~p"/environments")
  end

  test "authenticated with a host reaches the console", %{conn: conn} do
    configure_admin()
    put_plug(&__MODULE__.stub_with_hosts/1)

    {:ok, _view, html} = live(log_in(conn), ~p"/environments")
    assert html =~ "Environments"
  end

  test "settings is reachable with no hosts and shows the locked sidebar", %{conn: conn} do
    configure_admin()
    put_plug(&__MODULE__.stub_no_hosts/1)

    {:ok, _view, html} = live(log_in(conn), ~p"/settings")
    assert html =~ "Connect a host"
    # the full Infrastructure/Observability nav stays hidden until a host exists
    refute html =~ "Observability"
  end

  test "onboarding bounces to the console once a host exists", %{conn: conn} do
    configure_admin()
    put_plug(&__MODULE__.stub_with_hosts/1)

    assert {:error, {:redirect, %{to: "/environments"}}} = live(log_in(conn), ~p"/onboarding")
  end
end
