defmodule FuseWeb.SessionControllerTest do
  # async: false — toggles the global console-auth enforcement config.
  use FuseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @password "console-admin-secret"

  setup do
    prev = Application.get_env(:fuse, FuseWeb.Auth)
    Application.put_env(:fuse, FuseWeb.Auth, enforce: true)
    on_exit(fn -> Application.put_env(:fuse, FuseWeb.Auth, prev) end)
    :ok
  end

  describe "with an admin password configured" do
    setup do
      :ok = configure_admin(@password)
    end

    test "GET /login renders the sign-in form", %{conn: conn} do
      html = conn |> get(~p"/login") |> html_response(200)
      assert html =~ "Sign in"
      assert html =~ "Admin password"
    end

    test "POST /login with the correct password authenticates and redirects", %{conn: conn} do
      conn = post(conn, ~p"/login", %{"password" => @password})
      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :fuse_authenticated) == true
    end

    test "POST /login with a wrong password is rejected", %{conn: conn} do
      conn = post(conn, ~p"/login", %{"password" => "wrong"})
      assert html_response(conn, 401) =~ "Invalid password"
      refute get_session(conn, :fuse_authenticated)
    end

    test "the console redirects unauthenticated visitors to /login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/environments")
    end

    test "logout drops the session", %{conn: conn} do
      conn = post(conn, ~p"/login", %{"password" => @password})
      assert get_session(conn, :fuse_authenticated) == true

      conn = delete(conn, ~p"/logout")
      assert redirected_to(conn) == ~p"/login"
      refute get_session(conn, :fuse_authenticated)
    end
  end

  test "GET /login redirects to setup before any password is set", %{conn: conn} do
    assert redirected_to(get(conn, ~p"/login")) == ~p"/setup"
  end
end
