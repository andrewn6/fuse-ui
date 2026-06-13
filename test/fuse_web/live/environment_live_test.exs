defmodule FuseWeb.EnvironmentLiveTest do
  # async: false — swaps the global :fuse_client to the HTTP impl with a plug stub.
  # (The in-memory Fake stashes its pid in the *test* process dict, which the
  # separate LiveView process can't see; a Req plug runs in-process, so it works.)
  use FuseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @envs [
    %{
      "id" => "env_aaa111",
      "state" => "running",
      "task_id" => "task_alpha",
      "host_id" => "host_1",
      "spec" => %{"cpus" => 8, "ram_mb" => 16_384, "storage_gb" => 20},
      "created_at" => "2026-01-01T00:00:00Z",
      "updated_at" => "2026-01-01T00:00:00Z"
    },
    %{
      "id" => "env_bbb222",
      "state" => "provisioning",
      "task_id" => "task_beta",
      "spec" => %{"cpus" => 4, "ram_mb" => 8192, "storage_gb" => 10},
      "created_at" => "2026-01-01T00:00:00Z",
      "updated_at" => "2026-01-01T00:00:00Z"
    }
  ]

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
        "/v1/environments" -> %{"environments" => @envs}
        "/v1/hosts" -> %{"hosts" => []}
        "/v1/snapshots" -> %{"snapshots" => []}
        _ -> %{}
      end

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(body))
  end

  test "renders the environments console with decoded rows", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/environments")

    assert html =~ "Environments"
    assert html =~ "Sandboxed VM environments for agent tasks"
    assert html =~ "env_aaa111"
    assert html =~ "env_bbb222"
    assert html =~ "8 vCPU"
    assert html =~ "16 GB"
    assert html =~ "Running"
    assert html =~ "Provisioning"
    assert html =~ "task_alpha"
    assert html =~ "host_1"
    # The fuse wire has no per-env token; the UI must not invent one.
    refute html =~ "tok_"
  end

  test "state filter pills narrow the table", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/environments")

    view |> element("button[phx-value-state='running']") |> render_click()

    # Assert on the table rows specifically: confirm modals for all envs are
    # always present (hidden) in the DOM, so the raw id is not a reliable signal.
    assert has_element?(view, "#env-env_aaa111")
    refute has_element?(view, "#env-env_bbb222")
  end

  test "with a token configured, an authenticated session reaches the console", %{conn: conn} do
    Application.put_env(:fuse, FuseWeb.Plugs.ApiAuth, token: "dash-token")
    on_exit(fn -> Application.put_env(:fuse, FuseWeb.Plugs.ApiAuth, token: nil) end)

    conn = Plug.Test.init_test_session(conn, %{"fuse_authenticated" => true})

    {:ok, _view, html} = live(conn, ~p"/environments")
    assert html =~ "env_aaa111"
  end

  test "with a token configured, an unauthenticated session is redirected to login", %{conn: conn} do
    Application.put_env(:fuse, FuseWeb.Plugs.ApiAuth, token: "dash-token")
    on_exit(fn -> Application.put_env(:fuse, FuseWeb.Plugs.ApiAuth, token: nil) end)

    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/environments")
  end

  test "shows an error banner when fuse is unreachable", %{conn: conn} do
    # Simulate fuse being unreachable so the client returns {:error, transport}.
    Application.put_env(:fuse, Fuse.Client.HTTP,
      base_url: "http://fuse.test",
      token: "t",
      req_options: [retry: false, plug: fn conn -> Req.Test.transport_error(conn, :econnrefused) end]
    )

    {:ok, _view, html} = live(conn, ~p"/environments")
    assert html =~ "reach fuse"
  end
end
