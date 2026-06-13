defmodule FuseWeb.SnapshotLiveTest do
  # async: false — swaps the global :fuse_client to the HTTP impl with a plug stub.
  # (The in-memory Fake stashes its pid in the *test* process dict, which the
  # separate LiveView process can't see; a Req plug runs in-process, so it works.)
  use FuseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @snaps [
    %{
      "id" => "snap_aaa111",
      "vm_id" => "env_alpha",
      "state" => "ready",
      "mode" => "full",
      "size_bytes" => 1_288_490_188,
      "created_at" => "2026-01-01T00:00:00Z",
      "updated_at" => "2026-01-01T00:00:00Z"
    },
    %{
      "id" => "snap_bbb222",
      "vm_id" => "env_beta",
      "state" => "creating",
      "mode" => "incremental",
      "size_bytes" => nil,
      "created_at" => "2026-01-02T00:00:00Z",
      "updated_at" => "2026-01-02T00:00:00Z"
    }
  ]

  setup do
    prev_client = Application.get_env(:fuse, :fuse_client)
    prev_http = Application.get_env(:fuse, Fuse.Client.HTTP)

    Application.put_env(:fuse, :fuse_client, Fuse.Client.HTTP)

    Application.put_env(:fuse, Fuse.Client.HTTP,
      base_url: "http://fuse.test",
      token: "t",
      req_options: [retry: false, plug: &__MODULE__.stub/1]
    )

    on_exit(fn ->
      Application.put_env(:fuse, :fuse_client, prev_client)
      Application.put_env(:fuse, Fuse.Client.HTTP, prev_http)
    end)

    :ok
  end

  # Path-keyed stub. Restore (POST) and delete (DELETE) share /v1/snapshots/:id,
  # so disambiguate on conn.method; both return 200 with an empty body.
  def stub(%{request_path: "/v1/snapshots/" <> _id} = conn) do
    json(conn, %{})
  end

  def stub(conn) do
    body =
      case conn.request_path do
        "/v1/snapshots" -> %{"snapshots" => @snaps}
        "/v1/environments" -> %{"environments" => []}
        "/v1/hosts" -> %{"hosts" => []}
        _ -> %{}
      end

    json(conn, body)
  end

  defp json(conn, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(body))
  end

  test "renders the snapshots console with decoded rows", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/snapshots")

    assert html =~ "Snapshots"
    assert html =~ "VM snapshots"
    assert html =~ "snap_aaa111"
    assert html =~ "snap_bbb222"
    assert html =~ "env_alpha"
    assert html =~ "env_beta"
    assert html =~ "Ready"
    assert html =~ "Creating"
    # 1_288_490_188 bytes -> 1.2 GB (1024-based, one decimal).
    assert html =~ "1.2 GB"
    # nil size renders as a dash, not "0 B".
    assert html =~ "—"
  end

  test "state filter pills narrow the table", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/snapshots")

    html = view |> element("button[phx-value-state='ready']") |> render_click()

    assert html =~ "snap_aaa111"
    refute html =~ "snap_bbb222"
  end

  test "restoring a snapshot flashes success", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/snapshots")

    html = render_click(view, "restore", %{"id" => "snap_aaa111"})

    assert html =~ "Snapshot restore started."
  end

  test "deleting a snapshot flashes success", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/snapshots")

    html = render_click(view, "delete_snapshot", %{"id" => "snap_aaa111"})

    assert html =~ "Snapshot deleted."
  end

  test "shows an error banner when fuse is unreachable", %{conn: conn} do
    Application.put_env(:fuse, Fuse.Client.HTTP,
      base_url: "http://fuse.test",
      token: "t",
      req_options: [retry: false, plug: fn conn -> Req.Test.transport_error(conn, :econnrefused) end]
    )

    {:ok, _view, html} = live(conn, ~p"/snapshots")
    assert html =~ "reach fuse"
  end
end
