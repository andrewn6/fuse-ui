defmodule FuseWeb.Plugs.ApiAuthTest do
  # async: false — mutates the global ApiAuth token config and uses the sqlite sandbox.
  use FuseWeb.ConnCase, async: false

  @token "s3cr3t-control-plane-token"

  # Route an authenticated request to a working endpoint so a 200 proves the
  # plug let it through (Fake backs the context call).
  defp seed_fake do
    {:ok, _} = Fuse.Client.Fake.start_link()
    :ok
  end

  defp configure_token(token) do
    previous = Application.get_env(:fuse, FuseWeb.Plugs.ApiAuth)
    Application.put_env(:fuse, FuseWeb.Plugs.ApiAuth, token: token)
    on_exit(fn -> Application.put_env(:fuse, FuseWeb.Plugs.ApiAuth, previous) end)
  end

  describe "when a token is configured" do
    setup do
      configure_token(@token)
      seed_fake()
    end

    test "rejects a request with no Authorization header (401)", %{conn: conn} do
      conn = get(conn, "/api/v1/hosts")

      assert %{"errors" => %{"code" => "unauthorized", "message" => message}} =
               json_response(conn, 401)

      assert message == "missing or malformed credentials"
    end

    test "rejects a wrong token with a distinct message (401)", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer not-the-token")
        |> get("/api/v1/hosts")

      assert %{"errors" => %{"code" => "unauthorized", "message" => "invalid token"}} =
               json_response(conn, 401)
    end

    test "rejects a malformed Authorization header (401)", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Token #{@token}")
        |> get("/api/v1/hosts")

      assert %{"errors" => %{"code" => "unauthorized", "message" => "missing or malformed credentials"}} =
               json_response(conn, 401)
    end

    test "is case-sensitive on the Bearer scheme (mirrors fuse)", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "bearer #{@token}")
        |> get("/api/v1/hosts")

      assert json_response(conn, 401)
    end

    test "rejects an empty bearer token (401)", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer ")
        |> get("/api/v1/hosts")

      assert json_response(conn, 401)
    end

    test "accepts the correct token and reaches the endpoint (200)", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{@token}")
        |> get("/api/v1/hosts")

      assert %{"data" => []} = json_response(conn, 200)
    end

    test "guards writes too, not just reads (401 on POST without auth)", %{conn: conn} do
      conn = post(conn, "/api/v1/hosts", %{})
      assert json_response(conn, 401)
    end

    test "does not echo the configured token in the 401 body", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer wrong")
        |> get("/api/v1/hosts")

      refute conn.resp_body =~ @token
    end
  end

  describe "when no token is configured (insecure/dev mode)" do
    setup do
      configure_token(nil)
      seed_fake()
    end

    test "passes through without credentials (mirrors fuse empty-token no-op)", %{conn: conn} do
      conn = get(conn, "/api/v1/hosts")
      assert %{"data" => []} = json_response(conn, 200)
    end
  end
end
