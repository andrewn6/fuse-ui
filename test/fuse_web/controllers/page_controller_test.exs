defmodule FuseWeb.PageControllerTest do
  use FuseWeb.ConnCase

  test "GET / redirects to the environments console", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/environments"
  end
end
