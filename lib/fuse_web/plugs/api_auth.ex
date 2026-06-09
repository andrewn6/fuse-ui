defmodule FuseWeb.Plugs.ApiAuth do
  @moduledoc """
  Inbound bearer-token authentication for the control-plane `/api/v1`.

  Mirrors fuse's own `BearerAuth` semantics (see `fuse/api/middleware.go`) so the
  control plane authenticates callers the same way fuse does:

    * Credentials are taken from `Authorization: Bearer <token>` — the `Bearer `
      prefix is **case-sensitive**, exactly as fuse requires.
    * The presented token is compared against the configured token in
      **constant time** (`Plug.Crypto.secure_compare/2`) to avoid leaking it via
      timing.
    * When **no token is configured** the plug is a no-op pass-through
      (insecure/dev mode), matching fuse's "empty token disables auth" behaviour.
      This is also what lets the controller tests run without credentials.

  > #### Production {: .warning}
  >
  > A deployment with no `CONTROL_PLANE_TOKEN` set accepts **unauthenticated**
  > requests. Always set it in production. (Fail-closed-in-prod can be layered on
  > later if desired.)

  On failure it halts with `401` and the API's standard error envelope
  (`{"errors": {"code": "unauthorized", ...}}`, rendered via
  `FuseWeb.API.ErrorJSON`), distinguishing a missing/malformed header from a
  wrong token — again mirroring fuse.

  Note: this is the **inbound** token (callers -> control plane). It is distinct
  from the **outbound** fuse token (`Fuse.Client.HTTP` -> fuse).

  Configure with:

      config :fuse, FuseWeb.Plugs.ApiAuth, token: System.get_env("CONTROL_PLANE_TOKEN")
  """

  @behaviour Plug

  import Plug.Conn

  alias Fuse.Error

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case configured_token() do
      token when is_binary(token) and token != "" -> authenticate(conn, token)
      _ -> conn
    end
  end

  defp authenticate(conn, expected) do
    case bearer_token(conn) do
      {:ok, presented} ->
        if Plug.Crypto.secure_compare(presented, expected) do
          conn
        else
          unauthorized(conn, "invalid token")
        end

      :error ->
        unauthorized(conn, "missing or malformed credentials")
    end
  end

  # Case-sensitive "Bearer " prefix, single Authorization header, non-empty token.
  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" -> {:ok, token}
      _ -> :error
    end
  end

  defp unauthorized(conn, message) do
    body =
      FuseWeb.API.ErrorJSON.error(%{
        error: %Error{code: "unauthorized", message: message, status: 401}
      })

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(:unauthorized, Jason.encode!(body))
    |> halt()
  end

  defp configured_token do
    :fuse
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:token)
  end
end
