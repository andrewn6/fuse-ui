defmodule FuseWeb.EnvironmentShowTest do
  # async: false — swaps the global :fuse_client to the HTTP impl with a plug
  # stub (the in-memory Fake stashes its pid in the *test* process dict, which
  # the separate LiveView process can't see; a Req plug runs in-process).
  use FuseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Fuse.EventStream
  alias Fuse.EventStream.Event

  @env %{
    "id" => "env_aaa111",
    "state" => "running",
    "task_id" => "task_alpha",
    "host_id" => "host_1",
    "url" => "https://env.example.com",
    "spec" => %{
      "cpus" => 8,
      "ram_mb" => 16_384,
      "storage_gb" => 20,
      "region" => "us-east-1",
      "max_runtime_seconds" => 3600
    },
    "created_at" => "2026-01-01T00:00:00Z",
    "updated_at" => "2026-01-01T00:00:00Z"
  }

  setup do
    prev_client = Application.get_env(:fuse, :fuse_client)
    prev_http = Application.get_env(:fuse, Fuse.Client.HTTP)
    test_pid = self()

    Application.put_env(:fuse, :fuse_client, Fuse.Client.HTTP)

    Application.put_env(:fuse, Fuse.Client.HTTP,
      base_url: "http://fuse.test",
      token: "t",
      req_options: [retry: false, plug: fn conn -> __MODULE__.stub(conn, test_pid) end]
    )

    on_exit(fn ->
      Application.put_env(:fuse, :fuse_client, prev_client)
      Application.put_env(:fuse, Fuse.Client.HTTP, prev_http)
    end)

    :ok
  end

  def stub(conn, test_pid) do
    conn = Plug.Conn.fetch_query_params(conn)

    {status, body} =
      case {conn.method, conn.request_path} do
        {"GET", "/v1/environments/env_missing"} ->
          {404, %{"error" => %{"code" => "not_found", "message" => "no such environment"}}}

        {"GET", "/v1/environments/" <> _id} ->
          {200, @env}

        {"POST", "/v1/environments/" <> id} ->
          send(test_pid, {:action, conn.query_params["action"], id})
          {200, %{}}

        {"DELETE", "/v1/environments/" <> id} ->
          send(test_pid, {:destroyed, id})
          {200, ""}

        _ ->
          {200, %{}}
      end

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  defp event(attrs) do
    base = %{vm_id: "env_aaa111", kind: "state", updated_at: ~U[2026-01-01 00:00:05Z]}
    struct(Event, Map.merge(base, attrs))
  end

  defp push_event(id, event) do
    Phoenix.PubSub.broadcast(Fuse.PubSub, EventStream.topic(id), {:environment_event, event})
  end

  test "renders detail with spec, connection url and live state", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/environments/env_aaa111")

    assert html =~ "env_aaa111"
    assert html =~ "task_alpha"
    assert html =~ "us-east-1"
    # 16384 mb -> 16 gb, 3600 s -> 1 h
    assert html =~ "16 GB"
    assert html =~ "1 h"
    assert html =~ "https://env.example.com"
    assert html =~ "Running"
    # connected + active -> live indicator
    assert html =~ "Receiving live events"
  end

  test "a live event updates the state badge and appends to the log", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/environments/env_aaa111")

    push_event("env_aaa111", event(%{state: "draining", id: "evt1"}))
    html = render(view)

    assert html =~ "Draining"
    assert html =~ "1 events"
  end

  test "a terminal event drops the live indicator", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/environments/env_aaa111")
    assert html =~ "Receiving live events"

    push_event("env_aaa111", event(%{state: "destroyed", id: "evt9"}))
    html = render(view)

    assert html =~ "Destroyed"
    refute html =~ "Receiving live events"
  end

  test "a stream-down signal shows the disconnected notice", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/environments/env_aaa111")

    Phoenix.PubSub.broadcast(
      Fuse.PubSub,
      EventStream.topic("env_aaa111"),
      {:environment_stream_down, "env_aaa111",
       %Fuse.Error{code: "unavailable", message: "fuse is down"}}
    )

    html = render(view)

    assert html =~ "Event stream disconnected"
    assert html =~ "fuse is down"
  end

  test "an unknown environment renders the not-found state", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/environments/env_missing")

    assert html =~ "Environment not found"
    assert html =~ "Back to Environments"
  end

  test "drain confirms and calls fuse with action=drain", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/environments/env_aaa111")

    html = render_click(view, "drain", %{"id" => "env_aaa111"})

    assert_received {:action, "drain", "env_aaa111"}
    assert html =~ "Environment draining."
  end

  test "destroy navigates back to the list", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/environments/env_aaa111")

    assert {:error, {:live_redirect, %{to: "/environments"}}} =
             render_click(view, "destroy", %{"id" => "env_aaa111"})

    assert_received {:destroyed, "env_aaa111"}
  end
end
