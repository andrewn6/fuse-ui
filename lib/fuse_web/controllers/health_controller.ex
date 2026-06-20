defmodule FuseWeb.HealthController do
  @moduledoc """
  Unauthenticated health probes for orchestrators (load balancers, k8s).

    * `GET /healthz` — liveness: is *this* app process up? Always `200` if we can
      answer at all.
    * `GET /readyz` — readiness: are we ready to serve, i.e. is fuse reachable and
      ready? `200` when fuse is ok, `503` when degraded/unreachable, with the fuse
      status echoed in the body.
  """

  use FuseWeb, :controller

  alias Fuse.Health

  def live(conn, _params), do: json(conn, %{status: "ok"})

  def ready(conn, _params) do
    status = Health.check()
    code = if status == :ok, do: 200, else: 503

    conn
    |> put_status(code)
    |> json(%{status: to_string(status), fuse: to_string(status)})
  end
end
