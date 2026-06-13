defmodule FuseWeb.EnvironmentLiveActionsTest do
  # async: false — swaps the global :fuse_client to the HTTP impl with a plug
  # stub. (The in-memory Fake stashes its pid in the *test* process dict, which
  # the separate LiveView process can't see; a Req plug runs in-process.)
  #
  # Covers the create-environment modal and the per-row lifecycle actions
  # (drain / rotate-token / destroy) added on top of the read-only console.
  use FuseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @running %{
    "id" => "env_aaa111",
    "state" => "running",
    "task_id" => "task_alpha",
    "host_id" => "host_1",
    "spec" => %{"cpus" => 8, "ram_mb" => 16_384, "storage_gb" => 20},
    "created_at" => "2026-01-01T00:00:00Z",
    "updated_at" => "2026-01-01T00:00:00Z"
  }

  @provisioning %{
    "id" => "env_bbb222",
    "state" => "provisioning",
    "task_id" => "task_beta",
    "spec" => %{"cpus" => 4, "ram_mb" => 8192, "storage_gb" => 10},
    "created_at" => "2026-01-01T00:00:00Z",
    "updated_at" => "2026-01-01T00:00:00Z"
  }

  @created %{
    "id" => "env_ccc333",
    "state" => "provisioning",
    "task_id" => "task_gamma",
    "spec" => %{"cpus" => 1, "ram_mb" => 512, "storage_gb" => 10},
    "created_at" => "2026-01-02T00:00:00Z",
    "updated_at" => "2026-01-02T00:00:00Z"
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

  # The stub forwards each mutating request to the test process so assertions
  # can confirm the LiveView actually called fuse, then answers list reloads
  # from an Agent so a created/destroyed env shows up on the follow-up GET.
  def stub(conn, test_pid) do
    conn = Plug.Conn.fetch_query_params(conn)

    {status, body} =
      case {conn.method, conn.request_path} do
        {"GET", "/v1/environments"} ->
          {200, %{"environments" => current_envs(test_pid)}}

        {"POST", "/v1/environments"} ->
          send(test_pid, {:created, true})
          add_env(test_pid, @created)
          {200, @created}

        {"POST", "/v1/environments/" <> id} ->
          send(test_pid, {:action, conn.query_params["action"], id})
          {200, %{}}

        {"DELETE", "/v1/environments/" <> id} ->
          send(test_pid, {:destroyed, id})
          remove_env(test_pid, id)
          {200, ""}

        {"GET", "/v1/hosts"} ->
          {200, %{"hosts" => []}}

        {"GET", "/v1/snapshots"} ->
          {200, %{"snapshots" => []}}

        _ ->
          {200, %{}}
      end

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  # --- a tiny per-test env store, keyed by the test pid ---

  defp store(test_pid) do
    case Process.get({:env_store, test_pid}) do
      nil ->
        {:ok, agent} = Agent.start_link(fn -> [@running, @provisioning] end)
        Process.put({:env_store, test_pid}, agent)
        agent

      agent ->
        agent
    end
  end

  # The plug runs in the LiveView process, not the test process, so the Agent
  # is started lazily there and shared via that process's dictionary.
  defp current_envs(test_pid), do: Agent.get(store(test_pid), & &1)
  defp add_env(test_pid, env), do: Agent.update(store(test_pid), &(&1 ++ [env]))

  defp remove_env(test_pid, id),
    do: Agent.update(store(test_pid), fn envs -> Enum.reject(envs, &(&1["id"] == id)) end)

  # --- tests ---

  test "create-environment modal submits task_id + plan spec and reloads", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/environments")
    refute html =~ "env_ccc333"

    # Open the modal, then submit the form.
    html = view |> element("button", "Create environment") |> render_click()
    assert html =~ "Plan"

    html =
      view
      |> form("#create-environment form", environment: %{task_id: "task_gamma", plan: "tiny"})
      |> render_submit()

    assert_received {:created, true}
    # New row appears after the reload, and a success flash is shown.
    assert html =~ "env_ccc333"
    assert html =~ "Environment created."
    # NO-token accuracy rule: nothing token-shaped is ever rendered.
    refute html =~ "tok_"
  end

  test "drain action confirms, calls fuse with action=drain, and flashes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/environments")

    # Confirm modal's Drain button pushes the "drain" event for that row.
    html = render_click(view, "drain", %{"id" => "env_aaa111"})

    assert_received {:action, "drain", "env_aaa111"}
    assert html =~ "Environment draining."
  end

  test "rotate token calls fuse with action=rotate-token and flashes (no token shown)",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/environments")

    html = render_click(view, "rotate_token", %{"id" => "env_aaa111"})

    assert_received {:action, "rotate-token", "env_aaa111"}
    assert html =~ "Token rotated."
    refute html =~ "tok_"
  end

  test "destroy removes the row from the table after reload", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/environments")
    assert html =~ "env_aaa111"

    html = render_click(view, "destroy", %{"id" => "env_aaa111"})

    assert_received {:destroyed, "env_aaa111"}
    assert html =~ "Environment destroyed."
    refute html =~ "env_aaa111"
    # The other env is untouched.
    assert html =~ "env_bbb222"
  end

  test "a fuse error on an action surfaces as a flash and does not crash", %{conn: conn} do
    # Point the client at a plug that always 500s, so drain returns {:error,_}.
    Application.put_env(:fuse, Fuse.Client.HTTP,
      base_url: "http://fuse.test",
      token: "t",
      req_options: [
        retry: false,
        plug: fn conn ->
          conn = Plug.Conn.fetch_query_params(conn)

          body =
            case {conn.method, conn.request_path} do
              {"GET", "/v1/environments"} -> %{"environments" => [@running]}
              {"GET", "/v1/hosts"} -> %{"hosts" => []}
              {"GET", "/v1/snapshots"} -> %{"snapshots" => []}
              {"POST", _} -> %{"error" => %{"code" => "failed_precondition", "message" => "nope"}}
              _ -> %{}
            end

          status = if conn.method == "POST", do: 422, else: 200

          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(status, Jason.encode!(body))
        end
      ]
    )

    {:ok, view, _html} = live(conn, ~p"/environments")

    html = render_click(view, "drain", %{"id" => "env_aaa111"})

    assert html =~ "nope"
    # Still alive: the row is still rendered.
    assert html =~ "env_aaa111"
  end
end
