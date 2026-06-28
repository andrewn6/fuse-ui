defmodule FuseWeb.SettingsLiveTest do
  # async: false — swaps the global :fuse_client + toggles the ApiAuth token.
  use FuseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    prev_client = Application.get_env(:fuse, :fuse_client)
    prev_http = Application.get_env(:fuse, Fuse.Client.HTTP)
    prev_auth = Application.get_env(:fuse, FuseWeb.Plugs.ApiAuth)

    Application.put_env(:fuse, :fuse_client, Fuse.Client.HTTP)

    Application.put_env(:fuse, Fuse.Client.HTTP,
      base_url: "http://fuse.test",
      token: "t",
      req_options: [retry: false, plug: &__MODULE__.stub/1]
    )

    on_exit(fn ->
      Application.put_env(:fuse, :fuse_client, prev_client)
      Application.put_env(:fuse, Fuse.Client.HTTP, prev_http)
      Application.put_env(:fuse, FuseWeb.Plugs.ApiAuth, prev_auth)
    end)

    :ok
  end

  def stub(conn) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(
      200,
      Jason.encode!(%{"environments" => [], "hosts" => [], "snapshots" => []})
    )
  end

  test "shows the fuse endpoint and 'Not set' when no inbound token is configured", %{conn: conn} do
    Application.put_env(:fuse, FuseWeb.Plugs.ApiAuth, token: nil)

    {:ok, _view, html} = live(conn, ~p"/settings")
    assert html =~ "Settings"
    assert html =~ "http://fuse.test"
    assert html =~ "Not set"
  end

  test "shows 'Configured' (never the value) when an inbound token is set", %{conn: conn} do
    Application.put_env(:fuse, FuseWeb.Plugs.ApiAuth, token: "super-secret-value")
    # A configured token activates the auth gate, so authenticate the session.
    conn = Plug.Test.init_test_session(conn, %{"fuse_authenticated" => true})

    {:ok, _view, html} = live(conn, ~p"/settings")
    assert html =~ "Configured"
    # The token value must never be rendered.
    refute html =~ "super-secret-value"
  end
end
