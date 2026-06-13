defmodule FuseWeb.ActivityLiveTest do
  # async: false — swaps the global :fuse_client to the HTTP impl with a plug stub.
  use FuseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

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

  def stub(conn) do
    body =
      case conn.request_path do
        "/v1/environments" -> %{"environments" => []}
        "/v1/hosts" -> %{"hosts" => []}
        "/v1/snapshots" -> %{"snapshots" => []}
        _ -> %{}
      end

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(body))
  end

  test "renders the honest no-activity-feed state (fuse has no activity API)", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/activity")
    assert html =~ "Activity"
    assert html =~ "No activity feed yet"
    # Must not fabricate activity rows.
    refute html =~ "table"
  end
end
