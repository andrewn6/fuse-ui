defmodule FuseWeb.API.HostControllerTest do
  # async: false — sqlite sandbox + the Fake stashes its pid in the process dict,
  # and conn tests run inline in the test process.
  use FuseWeb.ConnCase, async: false

  setup do
    {:ok, _} = Fuse.Client.Fake.start_link()
    :ok
  end

  defp capacity, do: %{"cpus" => 8, "ram_mb" => 16_000, "storage_gb" => 100, "vm_count" => 0}

  defp register_body do
    %{"id" => "host-1", "url" => "https://host-1", "capacity" => capacity()}
  end

  defp register(conn, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/api/v1/hosts", Jason.encode!(body))
  end

  describe "POST /api/v1/hosts (register)" do
    test "registers a host and returns 201 with the serialized host", %{conn: conn} do
      conn = register(conn, register_body())

      assert %{"data" => data} = json_response(conn, 201)
      assert data["id"] == "host-1"
      assert data["url"] == "https://host-1"
      assert data["state"] == "active"
      assert data["capacity"]["cpus"] == 8
      assert data["capacity"]["ram_mb"] == 16_000
    end

    test "missing id returns 422 invalid_argument", %{conn: conn} do
      body = %{"url" => "https://host-1", "capacity" => capacity()}
      conn = register(conn, body)

      assert %{"errors" => %{"code" => "invalid_argument"} = errors} = json_response(conn, 422)
      assert is_binary(errors["message"])
    end

    test "missing url returns 422 invalid_argument", %{conn: conn} do
      body = %{"id" => "host-1", "capacity" => capacity()}
      conn = register(conn, body)

      assert %{"errors" => %{"code" => "invalid_argument"}} = json_response(conn, 422)
    end

    test "missing capacity returns 422 invalid_argument", %{conn: conn} do
      body = %{"id" => "host-1", "url" => "https://host-1"}
      conn = register(conn, body)

      assert %{"errors" => %{"code" => "invalid_argument"}} = json_response(conn, 422)
    end
  end

  describe "GET /api/v1/hosts (index)" do
    test "returns the array of registered hosts", %{conn: conn} do
      _ = register(build_conn(), register_body())

      _ =
        register(build_conn(), %{
          "id" => "host-2",
          "url" => "https://host-2",
          "capacity" => capacity()
        })

      conn = get(conn, "/api/v1/hosts")

      assert %{"data" => data} = json_response(conn, 200)
      assert is_list(data)
      ids = Enum.map(data, & &1["id"])
      assert "host-1" in ids
      assert "host-2" in ids
    end

    test "returns an empty array when no hosts are registered", %{conn: conn} do
      conn = get(conn, "/api/v1/hosts")
      assert %{"data" => []} = json_response(conn, 200)
    end
  end

  describe "GET /api/v1/hosts/:id (show)" do
    test "returns a single registered host", %{conn: conn} do
      _ = register(build_conn(), register_body())

      conn = get(conn, "/api/v1/hosts/host-1")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == "host-1"
      assert data["state"] == "active"
    end

    test "unknown host returns 404 not_found", %{conn: conn} do
      conn = get(conn, "/api/v1/hosts/nope")

      assert %{"errors" => %{"code" => "not_found"}} = json_response(conn, 404)
    end
  end

  describe "POST /api/v1/hosts/:id (update actions)" do
    setup %{conn: conn} do
      _ = register(build_conn(), register_body())
      {:ok, conn: conn}
    end

    test "?action=cordon returns 204 and flips state to cordoned", %{conn: conn} do
      cordon_conn = post(conn, "/api/v1/hosts/host-1?action=cordon")
      assert response(cordon_conn, 204) == ""

      show_conn = get(build_conn(), "/api/v1/hosts/host-1")
      assert %{"data" => %{"state" => "cordoned"}} = json_response(show_conn, 200)
    end

    test "?action=uncordon returns 204 and flips state back to active", %{conn: conn} do
      _ = post(build_conn(), "/api/v1/hosts/host-1?action=cordon")

      uncordon_conn = post(conn, "/api/v1/hosts/host-1?action=uncordon")
      assert response(uncordon_conn, 204) == ""

      show_conn = get(build_conn(), "/api/v1/hosts/host-1")
      assert %{"data" => %{"state" => "active"}} = json_response(show_conn, 200)
    end

    test "unknown action returns 400 invalid_argument inline", %{conn: conn} do
      conn = post(conn, "/api/v1/hosts/host-1?action=bogus")

      assert %{"errors" => %{"code" => "invalid_argument", "message" => message}} =
               json_response(conn, 400)

      assert message =~ "bogus"
    end

    test "missing action returns 400 invalid_argument inline", %{conn: conn} do
      conn = post(conn, "/api/v1/hosts/host-1")

      assert %{"errors" => %{"code" => "invalid_argument"}} = json_response(conn, 400)
    end

    test "cordon on unknown host returns 404 not_found", %{conn: conn} do
      conn = post(conn, "/api/v1/hosts/nope?action=cordon")

      assert %{"errors" => %{"code" => "not_found"}} = json_response(conn, 404)
    end

    test "uncordon on unknown host returns 404 not_found", %{conn: conn} do
      conn = post(conn, "/api/v1/hosts/nope?action=uncordon")

      assert %{"errors" => %{"code" => "not_found"}} = json_response(conn, 404)
    end
  end

  describe "DELETE /api/v1/hosts/:id (destroy)" do
    test "returns 204 and the host is gone afterwards", %{conn: conn} do
      _ = register(build_conn(), register_body())

      delete_conn = delete(conn, "/api/v1/hosts/host-1")
      assert response(delete_conn, 204) == ""

      show_conn = get(build_conn(), "/api/v1/hosts/host-1")
      assert %{"errors" => %{"code" => "not_found"}} = json_response(show_conn, 404)
    end

    test "deleting an unknown host returns 404 not_found", %{conn: conn} do
      conn = delete(conn, "/api/v1/hosts/nope")

      assert %{"errors" => %{"code" => "not_found"}} = json_response(conn, 404)
    end
  end
end
