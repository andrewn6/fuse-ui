defmodule Fuse.EventStream.Source.HTTPTest do
  # async: false — mutates the global Fuse.Client.HTTP config block.
  use ExUnit.Case, async: false

  alias Fuse.Error
  alias Fuse.EventStream.Source.HTTP

  # Only open/2's status branches are covered here: they return after headers,
  # before streaming. The long-lived 200 streaming/parse path can't be simulated
  # by Req's in-process plug (it runs to completion first) — that rides to the
  # Phase 10 integration gate. See PHASE5.md.

  defp with_plug(plug, fun) do
    previous = Application.get_env(:fuse, Fuse.Client.HTTP)

    Application.put_env(:fuse, Fuse.Client.HTTP,
      base_url: "http://fuse.test",
      token: "secret",
      req_options: [retry: false, plug: plug]
    )

    try do
      fun.()
    after
      Application.put_env(:fuse, Fuse.Client.HTTP, previous)
    end
  end

  defp respond(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  test "open hits the env events path with the events accept header" do
    with_plug(
      fn conn ->
        assert conn.request_path == "/v1/environments/vm-1/events"
        assert "text/event-stream" in Plug.Conn.get_req_header(conn, "accept")
        respond(conn, 404, %{})
      end,
      fn -> HTTP.open("vm-1", []) end
    )
  end

  test "open passes last_event_id as a query param when given" do
    with_plug(
      fn conn ->
        assert conn.query_string =~ "last_event_id=ev-7"
        respond(conn, 404, %{})
      end,
      fn -> HTTP.open("vm-1", last_event_id: "ev-7") end
    )
  end

  test "maps status codes to Error codes" do
    for {status, code} <- [
          {404, "not_found"},
          {409, "conflict"},
          {500, "internal"},
          {403, "unavailable"}
        ] do
      result =
        with_plug(
          fn conn -> respond(conn, status, %{}) end,
          fn -> HTTP.open("vm-1", []) end
        )

      assert {:error, %Error{code: ^code, status: ^status}} = result
    end
  end

  test "a 2xx returns an async-bodied response the consumer can read" do
    with_plug(
      fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/event-stream")
        |> Plug.Conn.send_resp(200, "data: {}\n\n")
      end,
      fn ->
        assert {:ok, %Req.Response{status: 200, body: %Req.Response.Async{}} = resp} =
                 HTTP.open("vm-1", [])

        assert :ok = HTTP.close(resp)
      end
    )
  end
end
