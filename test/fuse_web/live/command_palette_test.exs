defmodule FuseWeb.CommandPaletteTest do
  # async: false — swaps the global :fuse_client to the HTTP impl with a plug stub
  # so the palette's environment search has data to return.
  use FuseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @envs [
    %{
      "id" => "env_aaa111",
      "state" => "running",
      "task_id" => "task_alpha",
      "spec" => %{"cpus" => 1, "ram_mb" => 512, "storage_gb" => 10},
      "created_at" => "2026-01-01T00:00:00Z",
      "updated_at" => "2026-01-01T00:00:00Z"
    },
    %{
      "id" => "env_bbb222",
      "state" => "provisioning",
      "task_id" => "task_beta",
      "spec" => %{"cpus" => 1, "ram_mb" => 512, "storage_gb" => 10},
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

  test "the palette shell is present on every console screen", %{conn: conn} do
    for path <- [~p"/environments", ~p"/hosts", ~p"/snapshots", ~p"/settings"] do
      {:ok, _view, html} = live(conn, path)
      assert html =~ ~s(id="command-palette")
      assert html =~ "Search environments or jump to a screen"
    end
  end

  test "palette_search pushes matching environments back to the hook", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/environments")

    render_hook(view, "palette_search", %{"query" => "beta"})

    assert_push_event(view, "palette_results", %{
      results: [%{id: "env_bbb222", task_id: "task_beta", state: "provisioning"}]
    })
  end

  test "palette_search matches on env id too", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/environments")

    render_hook(view, "palette_search", %{"query" => "aaa111"})

    assert_push_event(view, "palette_results", %{results: [%{id: "env_aaa111"}]})
  end

  test "palette_search with no match returns an empty result set", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/environments")

    render_hook(view, "palette_search", %{"query" => "zzz"})

    assert_push_event(view, "palette_results", %{results: []})
  end

  test "palette_search caps results at 8", %{conn: conn} do
    many =
      for i <- 1..12 do
        %{
          "id" => "env_#{i}",
          "state" => "running",
          "task_id" => "task_#{i}",
          "spec" => %{"cpus" => 1, "ram_mb" => 512, "storage_gb" => 10},
          "created_at" => "2026-01-01T00:00:00Z",
          "updated_at" => "2026-01-01T00:00:00Z"
        }
      end

    Application.put_env(:fuse, Fuse.Client.HTTP,
      base_url: "http://fuse.test",
      token: "t",
      req_options: [
        retry: false,
        plug: fn conn ->
          body =
            case conn.request_path do
              "/v1/environments" -> %{"environments" => many}
              _ -> %{}
            end

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, Jason.encode!(body))
        end
      ]
    )

    {:ok, view, _html} = live(conn, ~p"/environments")

    render_hook(view, "palette_search", %{"query" => "env_"})

    assert_push_event(view, "palette_results", %{results: results})
    assert length(results) == 8
  end

  test "palette_search short-circuits on a blank query (no results)", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/environments")

    render_hook(view, "palette_search", %{"query" => "   "})

    assert_push_event(view, "palette_results", %{results: []})
  end

  test "palette_exec navigate redirects within the app", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/environments")

    render_hook(view, "palette_exec", %{"action" => "navigate", "to" => "/hosts"})

    assert_redirect(view, "/hosts")
  end

  test "palette_exec ignores non-local targets without crashing the view", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/environments")

    # the "/" <> _ guard rejects this; the catch-all swallows it so it never
    # reaches (and crashes) the host LiveView
    render_hook(view, "palette_exec", %{"action" => "navigate", "to" => "https://evil.example"})

    assert Process.alive?(view.pid)
  end
end
