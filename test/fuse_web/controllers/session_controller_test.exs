defmodule FuseWeb.SessionControllerTest do
  # async: false — toggles the global control-plane token config.
  use FuseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @token "dash-secret-token"

  setup do
    prev = Application.get_env(:fuse, FuseWeb.Plugs.ApiAuth)
    Application.put_env(:fuse, FuseWeb.Plugs.ApiAuth, token: @token)
    on_exit(fn -> Application.put_env(:fuse, FuseWeb.Plugs.ApiAuth, prev) end)
    :ok
  end

  test "GET /login renders the sign-in form", %{conn: conn} do
    html = conn |> get(~p"/login") |> html_response(200)
    assert html =~ "Sign in"
    assert html =~ "Control-plane token"
  end

  test "POST /login with the correct token authenticates and redirects", %{conn: conn} do
    conn = post(conn, ~p"/login", %{"token" => @token})
    assert redirected_to(conn) == ~p"/environments"
    assert get_session(conn, :fuse_authenticated) == true
  end

  test "POST /login with a wrong token is rejected", %{conn: conn} do
    conn = post(conn, ~p"/login", %{"token" => "wrong"})
    assert html_response(conn, 401) =~ "Invalid token"
    refute get_session(conn, :fuse_authenticated)
  end

  test "the console redirects unauthenticated visitors to /login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/environments")
  end

  test "logout drops the session", %{conn: conn} do
    conn = post(conn, ~p"/login", %{"token" => @token})
    assert get_session(conn, :fuse_authenticated) == true

    conn = delete(conn, ~p"/logout")
    assert redirected_to(conn) == ~p"/login"
    refute get_session(conn, :fuse_authenticated)
  end
end
