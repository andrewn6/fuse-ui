defmodule FuseWeb.Plugs.CidrAllowlist do
  @moduledoc """
  Restrict the control-plane API to a set of allowed source networks (CIDRs).

  fuse pairs its bearer auth with a network allowlist; this mirrors that so the
  control plane can be locked to known callers. The allowed ranges come from
  config (set from `CONTROL_PLANE_ALLOWED_CIDRS` in `runtime.exs`):

      config :fuse, FuseWeb.Plugs.CidrAllowlist, cidrs: ["10.0.0.0/8", "192.168.1.0/24"]

  When the list is empty (the default) the plug is a no-op pass-through — open to
  all sources. Otherwise a request whose `remote_ip` is in none of the ranges is
  rejected with `403` and the standard error envelope. Both IPv4 and IPv6 CIDRs
  are supported; an unparseable CIDR is ignored (logged once at boot would be
  nicer, but we keep the plug dependency-free).

  > #### Behind a proxy {: .info}
  >
  > `conn.remote_ip` is the peer address. If this app sits behind a load
  > balancer, put `RemoteIp` (or equivalent) ahead of it so the allowlist checks
  > the real client rather than the proxy.
  """

  @behaviour Plug

  import Plug.Conn
  import Bitwise

  alias Fuse.Error

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case parsed_cidrs() do
      [] -> conn
      cidrs -> if allowed?(conn.remote_ip, cidrs), do: conn, else: forbidden(conn)
    end
  end

  defp allowed?(ip, cidrs) when is_tuple(ip) do
    case ip_to_int(ip) do
      {:ok, ip_int, bits} -> Enum.any?(cidrs, &matches?(&1, ip_int, bits))
      :error -> false
    end
  end

  defp allowed?(_ip, _cidrs), do: false

  # a CIDR matches when, after dropping the host bits, the network parts are equal
  # and the address families (v4 vs v6) line up.
  defp matches?({net_int, prefix, bits}, ip_int, bits) do
    shift = bits - prefix
    ip_int >>> shift == net_int >>> shift
  end

  defp matches?(_cidr, _ip_int, _bits), do: false

  # --- config + parsing ---

  defp parsed_cidrs do
    :fuse
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:cidrs, [])
    |> Enum.flat_map(&parse_cidr/1)
  end

  defp parse_cidr(cidr) when is_binary(cidr) do
    with [addr, prefix_str] <- String.split(cidr, "/", parts: 2),
         {prefix, ""} <- Integer.parse(prefix_str),
         {:ok, tuple} <- :inet.parse_address(String.to_charlist(addr)),
         {:ok, net_int, bits} <- ip_to_int(tuple),
         true <- prefix >= 0 and prefix <= bits do
      [{net_int, prefix, bits}]
    else
      _ -> []
    end
  end

  defp parse_cidr(_), do: []

  # ipv4 -> {int, 32}; ipv6 -> {int, 128}
  defp ip_to_int({a, b, c, d}) do
    {:ok, (a <<< 24) + (b <<< 16) + (c <<< 8) + d, 32}
  end

  defp ip_to_int({a, b, c, d, e, f, g, h}) do
    int =
      [a, b, c, d, e, f, g, h]
      |> Enum.reduce(0, fn group, acc -> (acc <<< 16) + group end)

    {:ok, int, 128}
  end

  defp ip_to_int(_), do: :error

  defp forbidden(conn) do
    body =
      FuseWeb.API.ErrorJSON.error(%{
        error: %Error{
          code: "forbidden",
          message: "source address is not allowed",
          status: 403
        }
      })

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(:forbidden, Jason.encode!(body))
    |> halt()
  end
end
