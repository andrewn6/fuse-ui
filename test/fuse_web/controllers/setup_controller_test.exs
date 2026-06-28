defmodule FuseWeb.SetupControllerTest do
  # async: false — toggles the global console-auth enforcement config.
  use FuseWeb.ConnCase, async: false

  alias Fuse.Admin

  setup do
    prev = Application.get_env(:fuse, FuseWeb.Auth)
    Application.put_env(:fuse, FuseWeb.Auth, enforce: true)
    on_exit(fn -> Application.put_env(:fuse, FuseWeb.Auth, prev) end)
    :ok
  end

  test "GET /setup renders the create-password form when unconfigured", %{conn: conn} do
    html = conn |> get(~p"/setup") |> html_response(200)
    assert html =~ "Welcome to Fuse"
    assert html =~ "Admin password"
  end

  test "an unconfigured console funnels other browser requests to /setup", %{conn: conn} do
    assert redirected_to(get(conn, ~p"/login")) == ~p"/setup"
    assert redirected_to(get(conn, ~p"/environments")) == ~p"/setup"
  end

  test "POST /setup creates the password, authenticates, and redirects", %{conn: conn} do
    conn =
      post(conn, ~p"/setup", %{
        "password" => "first-password",
        "password_confirmation" => "first-password"
      })

    assert redirected_to(conn) == ~p"/"
    assert get_session(conn, :fuse_authenticated) == true
    assert Admin.configured?()
    assert Admin.verify_password("first-password")
  end

  test "POST /setup rejects mismatched passwords", %{conn: conn} do
    conn =
      post(conn, ~p"/setup", %{
        "password" => "first-password",
        "password_confirmation" => "different"
      })

    assert html_response(conn, 400) =~ "Passwords do not match"
    refute Admin.configured?()
  end

  test "POST /setup rejects a short password", %{conn: conn} do
    conn = post(conn, ~p"/setup", %{"password" => "short", "password_confirmation" => "short"})

    assert html_response(conn, 400) =~ "at least 8"
    refute Admin.configured?()
  end

  test "GET /setup redirects to /login once configured", %{conn: conn} do
    configure_admin()
    assert redirected_to(get(conn, ~p"/setup")) == ~p"/login"
  end

  test "POST /setup refuses to overwrite an existing password", %{conn: conn} do
    configure_admin("original-password")

    post(conn, ~p"/setup", %{
      "password" => "attacker-password",
      "password_confirmation" => "attacker-password"
    })

    assert Admin.verify_password("original-password")
    refute Admin.verify_password("attacker-password")
  end
end
