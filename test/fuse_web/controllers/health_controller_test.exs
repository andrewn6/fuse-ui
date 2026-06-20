defmodule FuseWeb.HealthControllerTest do
  use FuseWeb.ConnCase, async: true

  alias Fuse.Error

  setup do
    {:ok, _} = Fuse.Client.Fake.start_link()
    :ok
  end

  test "GET /healthz reports liveness regardless of fuse", %{conn: conn} do
    conn = get(conn, ~p"/healthz")
    assert json_response(conn, 200)["status"] == "ok"
  end

  test "GET /readyz is 200 when fuse is ready", %{conn: conn} do
    conn = get(conn, ~p"/readyz")
    body = json_response(conn, 200)
    assert body["status"] == "ok"
    assert body["fuse"] == "ok"
  end

  test "GET /readyz is 503 when fuse is unreachable", %{conn: conn} do
    :ok = Fuse.Client.Fake.stop()

    {:ok, _} =
      Fuse.Client.Fake.start_link(ready: {:error, %Error{code: "transport_error", message: "x"}})

    conn = get(conn, ~p"/readyz")
    assert json_response(conn, 503)["status"] == "unreachable"
  end

  test "GET /readyz is 503 (degraded) when fuse is up but not ready", %{conn: conn} do
    :ok = Fuse.Client.Fake.stop()

    {:ok, _} =
      Fuse.Client.Fake.start_link(
        ready: {:error, %Error{code: "unavailable", message: "x", status: 503}}
      )

    conn = get(conn, ~p"/readyz")
    assert json_response(conn, 503)["status"] == "degraded"
  end
end
