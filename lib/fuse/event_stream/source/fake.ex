defmodule Fuse.EventStream.Source.Fake do
  @moduledoc """
  In-memory `Fuse.EventStream.Source` for tests.

  It performs no network IO. A test drives a consumer by sending it messages
  tagged `{:fake_sse, vm_id, chunk}`, which `parse/2` hands back to the consumer
  as normalized chunks. `chunk` is `{:data, bytes}` (raw SSE-framed bytes, so the
  real `SSE.parse/1` path is exercised), `:done`, or `{:error, reason}`.

  `open/2` behaviour is controllable via `opts`:

    * `:result` — return this verbatim instead of `{:ok, handle}` (e.g.
      `{:error, %Fuse.Error{code: "not_found"}}` to simulate a missing env).
    * `:notify` — a pid that receives `{:fake_open, vm_id}` on each open, so
      reconnect tests can observe re-connection.
  """

  @behaviour Fuse.EventStream.Source

  @impl true
  def open(vm_id, opts) do
    if pid = opts[:notify], do: send(pid, {:fake_open, vm_id})
    Keyword.get(opts, :result, {:ok, %{vm_id: vm_id}})
  end

  @impl true
  def parse(%{vm_id: vm_id}, {:fake_sse, vm_id, chunk}) do
    case chunk do
      {:error, reason} -> {:error, reason}
      {:data, bytes} -> {:ok, [{:data, bytes}]}
      :done -> {:ok, [:done]}
    end
  end

  def parse(_handle, _message), do: :unknown

  @impl true
  def close(_handle), do: :ok
end
