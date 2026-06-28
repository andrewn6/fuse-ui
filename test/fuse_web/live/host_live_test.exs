defmodule FuseWeb.HostLiveTest do
  # async: false — swaps the global :fuse_client to the HTTP impl with a plug stub
  # (the in-memory Fake's pid lives in the test process; the LiveView runs elsewhere).
  use FuseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @host %{
    "id" => "host_1",
    "url" => "https://host-1.internal:8443",
    "region" => "us-east-1",
    "state" => "active",
    "capacity" => %{"cpus" => 16, "ram_mb" => 32_768, "storage_gb" => 500, "vm_count" => 48},
    "allocated" => %{"cpus" => 4, "ram_mb" => 8192, "storage_gb" => 100, "vm_count" => 6},
    "last_seen" => "2026-06-01T12:00:00Z",
    "created_at" => "2026-06-01T00:00:00Z",
    "updated_at" => "2026-06-01T12:00:00Z"
  }

  setup do
    prev_client = Application.get_env(:fuse, :fuse_client)
    prev_http = Application.get_env(:fuse, Fuse.Client.HTTP)
    Application.put_env(:fuse, :fuse_client, Fuse.Client.HTTP)
    put_plug(&__MODULE__.stub/1)

    on_exit(fn ->
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

  def stub(conn) do
    case {conn.method, conn.request_path} do
      {"GET", "/v1/hosts"} -> json(conn, %{"hosts" => [@host]})
      {"GET", "/v1/environments"} -> json(conn, %{"environments" => []})
      {"GET", "/v1/snapshots"} -> json(conn, %{"snapshots" => []})
      {"POST", "/v1/hosts"} -> json(conn, 201, %{"id" => "host_2", "state" => "active"})
      {"POST", _path} -> Plug.Conn.send_resp(conn, 204, "")
      {"DELETE", _path} -> Plug.Conn.send_resp(conn, 204, "")
      _ -> json(conn, %{})
    end
  end

  def stub_empty(conn) do
    case {conn.method, conn.request_path} do
      {"GET", "/v1/hosts"} -> json(conn, %{"hosts" => []})
      _ -> json(conn, %{"environments" => [], "snapshots" => []})
    end
  end

  test "renders host rows with state and capacity used/total", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/hosts")

    assert html =~ "host_1"
    assert html =~ "us-east-1"
    assert html =~ "Active"
    assert html =~ "4/16 vCPU"
    assert html =~ "8/32 GB"
    assert html =~ "6/48 VMs"
  end

  test "shows the host-onboarding empty state when the fleet is empty", %{conn: conn} do
    put_plug(&__MODULE__.stub_empty/1)

    {:ok, _view, html} = live(conn, ~p"/hosts")
    assert html =~ "Add your first host"
  end

  test "cordon action calls through and flashes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/hosts")

    html = view |> element("#host-host_1 button[phx-click='cordon']") |> render_click()
    assert html =~ "Host cordoned."
  end

  test "registering a host submits and flashes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/hosts")

    html =
      view
      |> form("form[phx-submit='register_host']",
        host: %{
          "id" => "host_2",
          "url" => "https://host-2.internal:8443",
          "region" => "us-east-1",
          "cpus" => "8",
          "ram_mb" => "16384",
          "storage_gb" => "200",
          "vm_count" => "0"
        }
      )
      |> render_submit()

    assert html =~ "Host registered."
  end

  test "the register form prefills the medium node preset and shows field hints", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/hosts")

    assert html =~ ~s(value="32")
    assert html =~ ~s(value="65536")
    assert html =~ "Total vCPUs to offer fuse."
    assert html =~ "Hard cap on concurrent microVMs"
  end

  test "choosing a node preset updates the capacity fields", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/hosts")

    html = render_click(view, "preset", %{"size" => "small"})
    assert html =~ ~s(value="8")
    refute html =~ ~s(value="32")

    html = render_click(view, "preset", %{"size" => "large"})
    assert html =~ ~s(value="64")
  end

  test "switching a preset preserves already-entered fields", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/hosts")

    # simulate typing id/url (phx-change), then pick a preset
    view
    |> form("form[phx-submit='register_host']", host: %{"id" => "host_x", "url" => "https://h"})
    |> render_change()

    html = render_click(view, "preset", %{"size" => "large"})

    assert html =~ ~s(value="host_x")
    assert html =~ ~s(value="64")
  end
end
