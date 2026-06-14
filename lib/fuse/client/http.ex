defmodule Fuse.Client.HTTP do
  @moduledoc """
  `Req`-based `Fuse.Client` implementation.

  Configure with:

      config :fuse, Fuse.Client.HTTP,
        base_url: "https://fuse.internal",
        token: System.get_env("FUSE_TOKEN"),
        req_options: []   # extra Req options merged into every request

  ## Request-ID propagation

  Each request carries an `X-Request-ID` header. If the calling process has a
  `:request_id` in its `Logger` metadata (Phoenix sets this via
  `Plug.RequestId`), that value is reused so logs correlate across the app and
  fuse; otherwise a fresh `req_<hex>` id is generated. This is **best-effort**:
  metadata only follows the same process, so a `Task`/GenServer hop will get a
  newly generated id rather than the originating request's.

  The bearer token and request bodies are never logged.
  """

  @behaviour Fuse.Client

  require Logger

  alias Fuse.Error

  # --- Environments ---

  @impl true
  def list_environments(filters) do
    with {:ok, body} <-
           request(:get, "/v1/environments", params: take(filters, [:task_id, :state, :host_id])) do
      {:ok, envelope(body, "environments")}
    end
  end

  @impl true
  def get_environment(id), do: request(:get, "/v1/environments/" <> enc(id))

  @impl true
  def create_environment(params), do: request(:post, "/v1/environments", json: params)

  @impl true
  def drain_environment(id),
    do: request(:post, "/v1/environments/" <> enc(id), params: %{action: "drain"})

  @impl true
  def rotate_token(id),
    do: request(:post, "/v1/environments/" <> enc(id), params: %{action: "rotate-token"})

  @impl true
  def destroy_environment(id), do: request(:delete, "/v1/environments/" <> enc(id))

  # --- Snapshots ---

  # `params` are forwarded verbatim as the JSON body, so callers must use fuse's
  # exact wire keys: comment, mode, retention_seconds, metadata, export_ref,
  # export_status.
  @impl true
  def create_snapshot(vm_id, params),
    do: request(:post, "/v1/environments/" <> enc(vm_id) <> "/snapshots", json: params)

  @impl true
  def list_snapshots(filters) do
    with {:ok, body} <-
           request(:get, "/v1/snapshots",
             params: take(filters, [:vm_id, :task_id, :tenant_id, :state])
           ) do
      {:ok, envelope(body, "snapshots")}
    end
  end

  @impl true
  def get_snapshot(id), do: request(:get, "/v1/snapshots/" <> enc(id))

  @impl true
  def restore_snapshot(id),
    do: request(:post, "/v1/snapshots/" <> enc(id), params: %{action: "restore"})

  @impl true
  def delete_snapshot(id), do: request(:delete, "/v1/snapshots/" <> enc(id))

  # --- Hosts ---

  @impl true
  def register_host(params), do: request(:post, "/v1/hosts", json: params)

  @impl true
  def list_hosts do
    with {:ok, body} <- request(:get, "/v1/hosts") do
      {:ok, envelope(body, "hosts")}
    end
  end

  @impl true
  def get_host(id), do: request(:get, "/v1/hosts/" <> enc(id))

  @impl true
  def cordon_host(id), do: request(:post, "/v1/hosts/" <> enc(id), params: %{action: "cordon"})

  @impl true
  def uncordon_host(id),
    do: request(:post, "/v1/hosts/" <> enc(id), params: %{action: "uncordon"})

  @impl true
  def remove_host(id), do: request(:delete, "/v1/hosts/" <> enc(id))

  # --- Health ---

  # Unauthenticated readiness probe. 200 -> ready; 503 -> reachable but a
  # dependency is unhealthy (mapped to a %Fuse.Error{status: 503} by request/3).
  @impl true
  def ready, do: request(:get, "/ready")

  # --- internals ---

  defp request(method, path, opts \\ []) do
    request_id = request_id()
    started = System.monotonic_time()

    result =
      base_options()
      |> Keyword.merge(opts)
      |> Keyword.merge(method: method, url: path)
      |> Keyword.update(:headers, [{"x-request-id", request_id}], fn headers ->
        [{"x-request-id", request_id} | headers]
      end)
      |> Req.request()

    duration_ms =
      System.convert_time_unit(System.monotonic_time() - started, :native, :millisecond)

    case result do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        log(:debug, method, path, status, request_id, duration_ms)
        {:ok, normalize(body)}

      {:ok, %Req.Response{status: status, body: body}} ->
        log(:warning, method, path, status, request_id, duration_ms)
        {:error, Error.parse(body, status)}

      {:error, exception} ->
        log(:warning, method, path, "transport_error", request_id, duration_ms)
        {:error, Error.transport(exception)}
    end
  end

  defp base_options do
    config = Application.get_env(:fuse, __MODULE__, [])

    base_url =
      config[:base_url] ||
        raise "missing :base_url config for #{inspect(__MODULE__)} (config :fuse, #{inspect(__MODULE__)}, base_url: ...)"

    auth =
      case config[:token] do
        token when is_binary(token) and token != "" -> [auth: {:bearer, token}]
        _ -> []
      end

    [base_url: base_url] ++ auth ++ (config[:req_options] || [])
  end

  # HTTP 204 / empty bodies come back as "" from Req.
  defp normalize(""), do: nil
  defp normalize(nil), do: nil
  defp normalize(body), do: body

  defp envelope(body, key) when is_map(body), do: Map.get(body, key, [])
  defp envelope(_body, _key), do: []

  # Keep only the allowed filter keys with non-nil values, accepting atom- or
  # string-keyed input.
  defp take(filters, keys) do
    for key <- keys, value = fetch(filters, key), not is_nil(value), into: %{}, do: {key, value}
  end

  defp fetch(map, key) when is_atom(key),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp enc(id), do: URI.encode(to_string(id))

  defp request_id do
    case Logger.metadata()[:request_id] do
      nil -> generate_request_id()
      id -> sanitize(to_string(id))
    end
  end

  defp generate_request_id,
    do: "req_" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

  # fuse requires X-Request-ID to match [A-Za-z0-9_-]{1,128}; scrub anything else.
  defp sanitize(id) do
    case id |> String.replace(~r/[^A-Za-z0-9_-]/, "") |> String.slice(0, 128) do
      "" -> generate_request_id()
      clean -> clean
    end
  end

  defp log(level, method, path, status, request_id, duration_ms) do
    Logger.log(
      level,
      "fuse #{method |> to_string() |> String.upcase()} #{path} -> #{status} (#{duration_ms}ms)",
      fuse_request_id: request_id,
      fuse_status: status,
      fuse_duration_ms: duration_ms
    )
  end
end
