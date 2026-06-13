defmodule FuseWeb.API.FallbackControllerTest do
  # async: false — ConnCase sqlite sandbox.
  use FuseWeb.ConnCase, async: false

  alias Fuse.Error
  alias FuseWeb.API.FallbackController

  # Drive the fallback directly: no controller action emits unauthorized/forbidden,
  # so the code->status map for those codes is otherwise dead/untested.
  defp render_error(conn, error) do
    conn
    |> Plug.Conn.put_private(:phoenix_endpoint, @endpoint)
    |> Phoenix.Controller.put_format("json")
    |> FallbackController.call({:error, error})
  end

  test "maps unauthorized -> 401 with the error envelope", %{conn: conn} do
    conn = render_error(conn, %Error{code: "unauthorized", message: "nope"})

    assert conn.status == 401

    assert Jason.decode!(conn.resp_body) ==
             %{"errors" => %{"code" => "unauthorized", "message" => "nope", "details" => nil}}
  end

  test "maps forbidden -> 403", %{conn: conn} do
    conn = render_error(conn, %Error{code: "forbidden", message: "denied"})
    assert conn.status == 403
  end

  test "prefers err.status over the code mapping when present", %{conn: conn} do
    conn = render_error(conn, %Error{code: "not_found", message: "x", status: 418})
    assert conn.status == 418
  end

  test "an unknown code falls back to 500", %{conn: conn} do
    conn = render_error(conn, %Error{code: "weird_code", message: "x"})
    assert conn.status == 500
  end
end
