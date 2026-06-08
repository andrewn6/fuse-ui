defmodule Fuse.EventStream.Source.HTTP do
  @moduledoc """
  `Req`-based `Fuse.EventStream.Source`.

  Opens `GET /v1/environments/{id}/events` with `into: :self`, so body bytes
  arrive as process messages to the owning consumer and `parse/2` is a thin
  delegate to `Req.parse_message/2`. Reuses the `Fuse.Client.HTTP` config block
  (`base_url`, `token`, `req_options`) for connection settings and auth.

  > #### Coverage {: .warning}
  >
  > This impl has no unit coverage in Phase 5: `Req.Test`'s in-process plug runs
  > to completion before Req yields a body, so it can't simulate long-lived
  > chunked SSE. Real-socket coverage rides to the Phase 10 integration gate.
  > The consumer logic is covered against `Source.Fake`.
  """

  @behaviour Fuse.EventStream.Source

  require Logger

  alias Fuse.Error

  @impl true
  def open(vm_id, opts) do
    path = "/v1/environments/" <> URI.encode(to_string(vm_id)) <> "/events"

    params =
      case opts[:last_event_id] do
        id when is_binary(id) and id != "" -> [last_event_id: id]
        _ -> []
      end

    request_opts =
      base_options()
      |> Keyword.merge(
        method: :get,
        url: path,
        into: :self,
        params: params,
        headers: [{"accept", "text/event-stream"}]
      )

    case Req.request(request_opts) do
      {:ok, %Req.Response{status: status} = resp} when status in 200..299 ->
        {:ok, resp}

      {:ok, %Req.Response{status: status} = resp} ->
        # Drop the (async) error-body socket; surface the status as an Error.
        cancel(resp)
        Logger.warning("fuse SSE open #{path} -> #{status}")
        {:error, %Error{code: code_for(status), message: "stream open failed", status: status}}

      {:error, exception} ->
        Logger.warning("fuse SSE open #{path} -> transport_error")
        {:error, Error.transport(exception)}
    end
  end

  @impl true
  def parse(%Req.Response{} = resp, message), do: Req.parse_message(resp, message)

  @impl true
  def close(%Req.Response{} = resp), do: cancel(resp)

  defp cancel(resp) do
    Req.cancel_async_response(resp)
    :ok
  rescue
    _ -> :ok
  end

  defp base_options do
    config = Application.get_env(:fuse, Fuse.Client.HTTP, [])

    base_url =
      config[:base_url] ||
        raise "missing :base_url config for Fuse.Client.HTTP (config :fuse, Fuse.Client.HTTP, base_url: ...)"

    auth =
      case config[:token] do
        token when is_binary(token) and token != "" -> [auth: {:bearer, token}]
        _ -> []
      end

    [base_url: base_url] ++ auth ++ (config[:req_options] || [])
  end

  defp code_for(404), do: "not_found"
  defp code_for(409), do: "conflict"
  defp code_for(status) when status in 500..599, do: "internal"
  defp code_for(_status), do: "unavailable"
end
