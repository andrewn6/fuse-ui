defmodule FuseWeb.Plugs.RateLimiter do
  @moduledoc """
  Fixed-window rate limiting for **write** requests on the control-plane API.

  Only mutating methods (`POST`/`PUT`/`PATCH`/`DELETE`) are counted; reads pass
  through uncounted. Each client (remote IP) gets `limit` writes per `window_ms`;
  over the limit returns `429` with the standard error envelope and a
  `Retry-After` header.

  A no-op when no positive `:limit` is configured (the dev/test default), so it
  never interferes unless a deployment turns it on:

      config :fuse, FuseWeb.Plugs.RateLimiter, limit: 60, window_ms: 60_000

  Counting is delegated to `FuseWeb.RateLimiter`, whose supervised process owns
  the backing ETS table.
  """

  @behaviour Plug

  import Plug.Conn

  alias Fuse.Error

  @write_methods ~w(POST PUT PATCH DELETE)

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: method} = conn, _opts) when method in @write_methods do
    config = config()

    case config[:limit] do
      limit when is_integer(limit) and limit > 0 ->
        enforce(conn, limit, config[:window_ms] || 60_000)

      _ ->
        conn
    end
  end

  # reads (and any non-write verb) are never rate limited
  def call(conn, _opts), do: conn

  defp enforce(conn, limit, window_ms) do
    case FuseWeb.RateLimiter.hit(client_key(conn), limit, window_ms) do
      {:allow, _count} -> conn
      {:deny, _count} -> too_many(conn, window_ms)
    end
  end

  # key on the peer IP; behind a proxy, configure RemoteIp upstream so this is
  # the real client rather than the load balancer.
  defp client_key(conn), do: :inet.ntoa(conn.remote_ip) |> to_string()

  defp too_many(conn, window_ms) do
    body =
      FuseWeb.API.ErrorJSON.error(%{
        error: %Error{
          code: "rate_limited",
          message: "too many requests; slow down",
          status: 429
        }
      })

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("retry-after", Integer.to_string(div(window_ms, 1000)))
    |> send_resp(:too_many_requests, Jason.encode!(body))
    |> halt()
  end

  defp config, do: Application.get_env(:fuse, __MODULE__, [])
end
