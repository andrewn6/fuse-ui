defmodule FuseWeb.API.EnvironmentControllerTest do
  # async: false — the sqlite sandbox locks across concurrent mix-test BEAMs, and
  # the Fake stashes its Agent pid in *this* process's dictionary (conn tests run
  # the controller/context inline in the test process).
  use FuseWeb.ConnCase, async: false

  setup do
    {:ok, _} =
      Fuse.Client.Fake.start_link(environments: [%{id: "env-1", state: "running", task_id: "t1"}])

    :ok
  end

  defp post_json(conn, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(body))
  end

  describe "index" do
    test "lists environments", %{conn: conn} do
      conn = get(conn, "/api/v1/environments")
      assert %{"data" => [env]} = json_response(conn, 200)
      assert env["id"] == "env-1"
      assert env["task_id"] == "t1"
    end

    test "filters by task_id", %{conn: conn} do
      conn = get(conn, "/api/v1/environments?task_id=t1")
      assert %{"data" => [%{"id" => "env-1"}]} = json_response(conn, 200)
    end

    test "filters out non-matching task_id", %{conn: conn} do
      conn = get(conn, "/api/v1/environments?task_id=nope")
      assert %{"data" => []} = json_response(conn, 200)
    end
  end

  describe "create" do
    test "creates an environment and returns 201", %{conn: conn} do
      body = %{
        "task_id" => "t1",
        "spec" => %{"cpus" => 1, "ram_mb" => 512, "storage_gb" => 10}
      }

      conn = post_json(conn, "/api/v1/environments", body)

      assert %{"data" => data} = json_response(conn, 201)
      assert is_binary(data["id"])
      assert data["state"] == "provisioning"
    end

    test "missing spec returns 422 invalid_argument", %{conn: conn} do
      conn = post_json(conn, "/api/v1/environments", %{"task_id" => "t1"})

      assert %{"errors" => %{"code" => "invalid_argument"}} = json_response(conn, 422)
    end

    test "missing task_id returns 422 invalid_argument", %{conn: conn} do
      body = %{"spec" => %{"cpus" => 1, "ram_mb" => 512, "storage_gb" => 10}}
      conn = post_json(conn, "/api/v1/environments", body)

      assert %{"errors" => %{"code" => "invalid_argument"}} = json_response(conn, 422)
    end
  end

  describe "show" do
    test "returns the environment", %{conn: conn} do
      conn = get(conn, "/api/v1/environments/env-1")
      assert %{"data" => %{"id" => "env-1"}} = json_response(conn, 200)
    end

    test "unknown id returns 404 not_found", %{conn: conn} do
      conn = get(conn, "/api/v1/environments/nope")
      assert %{"errors" => %{"code" => "not_found"}} = json_response(conn, 404)
    end
  end

  describe "update actions" do
    test "drain returns 200 with draining state", %{conn: conn} do
      conn = post(conn, "/api/v1/environments/env-1?action=drain")
      assert %{"data" => %{"state" => "draining"}} = json_response(conn, 200)
    end

    test "rotate-token returns 204", %{conn: conn} do
      conn = post(conn, "/api/v1/environments/env-1?action=rotate-token")
      assert response(conn, 204)
    end

    test "bogus action returns 400 invalid_argument", %{conn: conn} do
      conn = post(conn, "/api/v1/environments/env-1?action=bogus")

      assert %{"errors" => %{"code" => "invalid_argument", "message" => message}} =
               json_response(conn, 400)

      assert message =~ "bogus"
    end

    test "missing action returns 400 invalid_argument", %{conn: conn} do
      conn = post(conn, "/api/v1/environments/env-1")
      assert %{"errors" => %{"code" => "invalid_argument"}} = json_response(conn, 400)
    end

    test "drain on non-existent env returns 404 not_found", %{conn: conn} do
      conn = post(conn, "/api/v1/environments/nope?action=drain")
      assert %{"errors" => %{"code" => "not_found"}} = json_response(conn, 404)
    end

    test "rotate-token on non-existent env returns 404 not_found", %{conn: conn} do
      conn = post(conn, "/api/v1/environments/nope?action=rotate-token")
      assert %{"errors" => %{"code" => "not_found"}} = json_response(conn, 404)
    end
  end

  describe "destroy" do
    test "removes the environment then show returns 404", %{conn: conn} do
      conn = delete(conn, "/api/v1/environments/env-1")
      assert response(conn, 204)

      conn = get(conn, "/api/v1/environments/env-1")
      assert %{"errors" => %{"code" => "not_found"}} = json_response(conn, 404)
    end

    test "destroy on non-existent env returns 404 not_found", %{conn: conn} do
      conn = delete(conn, "/api/v1/environments/nope")
      assert %{"errors" => %{"code" => "not_found"}} = json_response(conn, 404)
    end
  end
end
