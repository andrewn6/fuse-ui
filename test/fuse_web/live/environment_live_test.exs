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
      req_options: [
        retry: false,
        plug: fn conn -> Req.Test.transport_error(conn, :econnrefused) end
      ]
    )

    {:ok, _view, html} = live(conn, ~p"/environments")
    assert html =~ "reach fuse"
  end

  test "the bottom command bar shows visible-of-total and filters by query", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/environments")
    assert html =~ "of 2"
    # no clear control until a filter is active
    refute has_element?(view, "button[phx-click='clear_filters']")

    html =
      view
      |> form("form[phx-change='refine']", %{"query" => "beta"})
      |> render_change()

    # total is unchanged; the query narrowed the rows to the matching task
    assert html =~ "of 2"
    assert has_element?(view, "button[phx-click='clear_filters']")
    refute has_element?(view, "#env-env_aaa111")
    assert has_element?(view, "#env-env_bbb222")

    # clearing restores every row
    view |> element("button[phx-click='clear_filters']") |> render_click()
    assert has_element?(view, "#env-env_aaa111")
    assert has_element?(view, "#env-env_bbb222")
  end

  test "changing the sort keeps the rows and does not crash", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/environments")

    view
    |> form("form[phx-change='refine']", %{"sort" => "id_asc"})
    |> render_change()

    assert has_element?(view, "#env-env_aaa111")
    assert has_element?(view, "#env-env_bbb222")
  end

  test "sort reorders the table by created and by state", %{conn: conn} do
    old = %{
      "id" => "env_old",
      "state" => "running",
      "task_id" => "t1",
      "spec" => %{"cpus" => 1, "ram_mb" => 512, "storage_gb" => 10},
      "created_at" => "2026-01-01T00:00:00Z"
    }

    new = %{
      "id" => "env_new",
      "state" => "provisioning",
      "task_id" => "t2",
      "spec" => %{"cpus" => 1, "ram_mb" => 512, "storage_gb" => 10},
      "created_at" => "2026-03-01T00:00:00Z"
    }

    stub_envs([old, new])
    {:ok, view, html} = live(conn, ~p"/environments")

    # default sort is created_desc: newest first
    assert pos(html, "env-env_new") < pos(html, "env-env_old")

    html = sort(view, "created_asc")
    assert pos(html, "env-env_old") < pos(html, "env-env_new")

    # state sort is alphabetical: provisioning (env_new) before running (env_old)
    html = sort(view, "state")
    assert pos(html, "env-env_new") < pos(html, "env-env_old")
  end

  test "a missing created_at does not crash the default (created) sort", %{conn: conn} do
    dated = %{
      "id" => "env_dated",
      "state" => "running",
      "task_id" => "t1",
      "spec" => %{"cpus" => 1, "ram_mb" => 512, "storage_gb" => 10},
      "created_at" => "2026-01-01T00:00:00Z"
    }

    # no created_at -> decodes to nil; created_key/1 must sort it to the boundary
    undated = %{
      "id" => "env_undated",
      "state" => "running",
      "task_id" => "t2",
      "spec" => %{"cpus" => 1, "ram_mb" => 512, "storage_gb" => 10}
    }

    stub_envs([dated, undated])
    {:ok, view, _html} = live(conn, ~p"/environments")

    assert has_element?(view, "#env-env_dated")
    assert has_element?(view, "#env-env_undated")

    # the asc branch uses the same nil-safe key
    sort(view, "created_asc")
    assert has_element?(view, "#env-env_dated")
    assert has_element?(view, "#env-env_undated")
  end

  test "the sidebar shows the real fuse endpoint and drops the boilerplate", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/environments")

    assert html =~ "fuse.test"
    refute html =~ "flint"
    refute html =~ "usr_10vd"
    refute html =~ "prod · us-east-1"
  end

  test "the sidebar reflects live fuse reachability", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/environments")
    # the connected mount polls /ready (plug catch-all -> 200); render/1 flushes it
    assert render(view) =~ "Connected"
  end

  @host %{
    "id" => "host_1",
    "state" => "active",
    "region" => "us-east-1",
    "capacity" => %{"cpus" => 8, "ram_mb" => 16_384, "storage_gb" => 100, "vm_count" => 4},
    "allocated" => %{"cpus" => 0, "ram_mb" => 0, "storage_gb" => 0, "vm_count" => 0}
  }

  test "onboarding shows with no environments and gates create until a host exists", %{conn: conn} do
    stub_fleet([], [])
    {:ok, view, html} = live(conn, ~p"/environments")

    assert html =~ "Get started"
    assert html =~ "Register a host first"
    # the onboarding CTA (not the always-present sidebar nav link)
    assert has_element?(view, "a[href='/hosts']", "Register host")
    refute has_element?(view, "button[phx-click='open_create']")
  end

  test "onboarding marks the host step done and enables create once a host exists", %{conn: conn} do
    stub_fleet([], [@host])
    {:ok, view, html} = live(conn, ~p"/environments")

    assert html =~ "Get started"
    assert html =~ "Registered"
    assert has_element?(view, "button[phx-click='open_create']")
    # the onboarding register-host CTA is gone (sidebar nav link is unaffected)
    refute has_element?(view, "a[href='/hosts']", "Register host")
  end

  test "no onboarding once environments exist", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/environments")
    refute html =~ "Get started"
  end

  # --- helpers ---

  defp stub_envs(envs), do: stub_fleet(envs, [])

  defp stub_fleet(envs, hosts) do
    Application.put_env(:fuse, Fuse.Client.HTTP,
      base_url: "http://fuse.test",
      token: "t",
      req_options: [
        retry: false,
        plug: fn conn ->
          body =
            case conn.request_path do
              "/v1/environments" -> %{"environments" => envs}
              "/v1/hosts" -> %{"hosts" => hosts}
              "/v1/snapshots" -> %{"snapshots" => []}
              _ -> %{}
            end

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, Jason.encode!(body))
        end
      ]
    )
  end

  defp sort(view, value) do
    view |> form("form[phx-change='refine']", %{"sort" => value}) |> render_change()
  end

  defp pos(html, needle) do
    {start, _} = :binary.match(html, needle)
    start
  end
end
