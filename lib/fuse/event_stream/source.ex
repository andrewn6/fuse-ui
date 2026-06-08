defmodule Fuse.EventStream.Source do
  @moduledoc """
  Behaviour for opening and reading an environment event stream.

  Kept separate from `Fuse.Client` because a long-lived SSE stream doesn't fit
  that module's synchronous `{:ok, map}` request/response contract. A source
  `open/2`s a stream (returning a `handle`), turns each incoming process message
  into normalized `chunk`s via `parse/2`, and `close/1`s when done.

  The contract mirrors `Req.parse_message/2` (the HTTP impl is a thin delegate):
  body bytes arrive as `{:data, binary}`, end-of-stream as `:done`, unrelated
  messages return `:unknown`, and transport failures return `{:error, reason}`.

  Swap implementations with `config :fuse, :event_source, ...` (defaults to
  `Fuse.EventStream.Source.HTTP`).
  """

  alias Fuse.Error

  @type handle :: term()
  @type chunk :: {:data, binary()} | :done | {:trailers, term()}

  @doc """
  Open the SSE stream for `vm_id`. Returns after response headers.

  `opts` may include `:last_event_id` (forward-compat resume cursor — fuse v1
  ignores it). A non-2xx status (e.g. 404 for a missing env) returns
  `{:error, %Fuse.Error{}}`.
  """
  @callback open(vm_id :: String.t(), opts :: keyword()) ::
              {:ok, handle()} | {:error, Error.t()}

  @doc "Translate one received process message into stream chunks."
  @callback parse(handle(), message :: term()) ::
              {:ok, [chunk()]} | :unknown | {:error, term()}

  @doc "Tear down the stream / underlying socket."
  @callback close(handle()) :: :ok

  @doc "The configured source implementation."
  @spec impl() :: module()
  def impl, do: Application.get_env(:fuse, :event_source, Fuse.EventStream.Source.HTTP)
end
