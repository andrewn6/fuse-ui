defmodule FuseWeb.OnboardingLiveTest do
  # async: false — toggles the global console-auth + fuse-client config.
  use FuseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    prev_auth = Application.get_env(:fuse, FuseWeb.Auth)
    prev_client = Application.get_env(:fuse, :fuse_client)
    prev_http = Application.get_env(:fuse, Fuse.Client.HTTP)

    Application.put_env(:fuse, FuseWeb.Auth, enforce: true)
    Application.put_env(:fuse, :fuse_client, Fuse.Client.HTTP)

    Application.put_env(:fuse, Fuse.Client.HTTP,
      base_url: "http://fuse.test",
      token: "t",
      req_options: [retry: false, plug: &__MODULE__.stub/1]
    )

    on_exit(fn ->
      Application.put_env(:fuse, FuseWeb.Auth, prev_auth)
      Application.put_env(:fuse, :fuse_client, prev_client)
      Application.put_env(:fuse, Fuse.Client.HTTP, prev_http)
    end)

    :ok = configure_admin()
    :ok
  end

  defp json(conn, status \\ 200, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  # empty fleet so the gate routes to onboarding; register returns a new host
  def stub(conn) do
    case {conn.method, conn.request_path} do
      {"GET", "/v1/hosts"} -> json(conn, %{"hosts" => []})
      {"POST", "/v1/hosts"} -> json(conn, 201, %{"id" => "host_1", "state" => "active"})
      {"GET", "/ready"} -> json(conn, %{"status" => "ok"})
      _ -> json(conn, %{"environments" => [], "snapshots" => []})
    end
  end

  test "renders the connect-a-host funnel with the medium preset prefilled", %{conn: conn} do
    {:ok, _view, html} = live(log_in(conn), ~p"/onboarding")

    assert html =~ "Connect your first host"
    assert html =~ "Total vCPUs to offer fuse."
    assert html =~ ~s(value="32")
  end

  test "registering the first host navigates to the console", %{conn: conn} do
    {:ok, view, _html} = live(log_in(conn), ~p"/onboarding")

    result =
      view
      |> form("form[phx-submit='register_host']",
        host: %{
          "id" => "host_1",
          "url" => "https://host-1.internal:8443",
          "region" => "us-east-1",
          "cpus" => "8",
          "ram_mb" => "16384",
          "storage_gb" => "200",
          "vm_count" => "8"
        }
      )
      |> render_submit()

    assert {:error, {:live_redirect, %{to: "/environments"}}} = result
  end
end
