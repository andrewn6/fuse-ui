defmodule FuseWeb.API.SnapshotControllerTest do
  # async: false — the sqlite sandbox can't handle concurrent BEAMs, and the
  # Fake stashes its Agent pid in this (the test) process dictionary, so conn
  # requests must run inline in the same process.
  use FuseWeb.ConnCase, async: false

  setup do
    # Seed an environment so snapshot creation has a vm to target.
    {:ok, _} =
      Fuse.Client.Fake.start_link(environments: [%{id: "vm-1", state: "running", task_id: "t"}])

    :ok
  end

  # Create a snapshot and return its serialized data map.
  defp create_snapshot(conn) do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/v1/environments/vm-1/snapshots",
        Jason.encode!(%{"comment" => "c", "mode" => "full"})
      )

    json_response(conn, 201)["data"]
  end

  describe "POST /api/v1/environments/:vm_id/snapshots (create)" do
    test "creates a snapshot for an existing vm -> 201", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          "/api/v1/environments/vm-1/snapshots",
          Jason.encode!(%{"comment" => "nightly", "mode" => "full"})
        )

      assert %{"data" => data} = json_response(conn, 201)
      assert data["vm_id"] == "vm-1"
      assert data["state"] == "creating"
      assert data["comment"] == "nightly"
      assert is_binary(data["id"])
    end

    test "create on a missing vm -> 404 not_found", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/environments/nope/snapshots", Jason.encode!(%{"comment" => "c"}))

      assert %{"errors" => errors} = json_response(conn, 404)
      assert errors["code"] == "not_found"
      assert is_binary(errors["message"])
    end
  end

  describe "GET /api/v1/snapshots (index)" do
    test "returns a data array", %{conn: conn} do
      _ = create_snapshot(conn)

      conn = get(build_conn(), "/api/v1/snapshots")
      assert %{"data" => data} = json_response(conn, 200)
      assert is_list(data)
      assert length(data) == 1
      assert hd(data)["vm_id"] == "vm-1"
    end
  end

  describe "GET /api/v1/snapshots/:id (show)" do
    test "shows an existing snapshot -> 200", %{conn: conn} do
      created = create_snapshot(conn)

      conn = get(build_conn(), "/api/v1/snapshots/#{created["id"]}")
      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == created["id"]
      assert data["vm_id"] == "vm-1"
    end

    test "unknown snapshot -> 404 not_found", %{conn: conn} do
      conn = get(conn, "/api/v1/snapshots/nope")
      assert %{"errors" => errors} = json_response(conn, 404)
      assert errors["code"] == "not_found"
    end
  end

  describe "POST /api/v1/snapshots/:id (update / action dispatch)" do
    test "?action=restore on a created snapshot -> 204", %{conn: conn} do
      created = create_snapshot(conn)

      conn = post(build_conn(), "/api/v1/snapshots/#{created["id"]}?action=restore")
      assert response(conn, 204) == ""
    end

    test "?action=bogus -> 400 invalid_argument", %{conn: conn} do
      conn = post(conn, "/api/v1/snapshots/snap-1?action=bogus")
      assert %{"errors" => errors} = json_response(conn, 400)
      assert errors["code"] == "invalid_argument"
      assert errors["message"] =~ "bogus"
    end

    test "missing action -> 400 invalid_argument", %{conn: conn} do
      conn = post(conn, "/api/v1/snapshots/snap-1")
      assert %{"errors" => errors} = json_response(conn, 400)
      assert errors["code"] == "invalid_argument"
    end

    test "?action=restore on unknown snapshot -> 404 not_found", %{conn: conn} do
      conn = post(conn, "/api/v1/snapshots/nope?action=restore")
      assert %{"errors" => errors} = json_response(conn, 404)
      assert errors["code"] == "not_found"
    end
  end

  describe "DELETE /api/v1/snapshots/:id (destroy)" do
    test "destroys a created snapshot -> 204, then show -> 404", %{conn: conn} do
      created = create_snapshot(conn)

      del_conn = delete(build_conn(), "/api/v1/snapshots/#{created["id"]}")
      assert response(del_conn, 204) == ""

      show_conn = get(build_conn(), "/api/v1/snapshots/#{created["id"]}")
      assert %{"errors" => errors} = json_response(show_conn, 404)
      assert errors["code"] == "not_found"
    end

    test "destroy unknown snapshot -> 404 not_found", %{conn: conn} do
      conn = delete(conn, "/api/v1/snapshots/nope")
      assert %{"errors" => errors} = json_response(conn, 404)
      assert errors["code"] == "not_found"
    end
  end
end
