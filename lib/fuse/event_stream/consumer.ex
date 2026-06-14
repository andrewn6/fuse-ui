defmodule Fuse.EventStream.Consumer do
  @moduledoc """
  Owns one environment's SSE stream and rebroadcasts decoded events to PubSub.

  One process per `vm_id`. It opens a `Fuse.EventStream.Source`, folds incoming
  body bytes through the pure `Fuse.EventStream.SSE` parser, decodes each frame
  into a `Fuse.EventStream.Event`, and broadcasts `{:environment_event, event}`
  to the `"environments"` and `"environment:{vm_id}"` topics.

  Lifecycle (per `PHASE5.md`), keyed on the **decoded event state**, not EOF
  timing:

    * terminal event (`destroyed`/`failed`) → broadcast, then stop. No reconnect.
    * open returns a permanent error (e.g. 404) → broadcast
      `{:environment_stream_down, vm_id, error}`, then stop. No reconnect.
    * unexpected EOF / transport error / transient open error → reconnect with
      exponential backoff (forward-compat `last_event_id`; fuse v1 ignores it, so
      a fresh snapshot arrives and transitions during the gap are missed).

  ## Options

    * `:vm_id` (required)
    * `:name` — GenServer name (the supervisor registers via `Registry`)
    * `:source` — `Fuse.EventStream.Source` impl (default: configured impl)
    * `:source_opts` — extra opts passed to `source.open/2`
    * `:pubsub` — PubSub server (default `Fuse.PubSub`)
    * `:subscriber` — a pid to monitor; the consumer self-stops when its last
      monitored subscriber exits (use `add_subscriber/2` to register more). A
      consumer started with no subscriber is never torn down this way.
    * `:backoff_initial` / `:backoff_max` — reconnect backoff in ms (default 1000 / 30000)
  """

  # :transient — a normal stop (terminal event or permanent open error like 404)
  # stays stopped; only a genuine crash auto-restarts. :permanent would restart
  # on the :normal terminal stop, reconnect, 404 on the destroyed env, and
  # crash-loop until max_restarts took down the whole EventStream.Supervisor.
  use GenServer, restart: :transient

  require Logger

  alias Fuse.Error
  alias Fuse.EventStream.Event
  alias Fuse.EventStream.SSE
  alias Fuse.EventStream.Source

  # Open errors with these codes won't self-heal, so we stop instead of looping.
  @permanent_codes ~w(not_found invalid_argument conflict)

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    gen_opts = if name = opts[:name], do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc "Register `pid` as a subscriber to monitor; the consumer stops when its last leaves."
  @spec add_subscriber(GenServer.server(), pid()) :: :ok
  def add_subscriber(server, pid) when is_pid(pid),
    do: GenServer.cast(server, {:add_subscriber, pid})

  @impl true
  def init(opts) do
    vm_id = Keyword.fetch!(opts, :vm_id)
    initial = Keyword.get(opts, :backoff_initial, 1000)

    state = %{
      vm_id: vm_id,
      source: Keyword.get(opts, :source) || Source.impl(),
      source_opts: Keyword.get(opts, :source_opts, []),
      pubsub: Keyword.get(opts, :pubsub, Fuse.PubSub),
      handle: nil,
      buffer: "",
      last_event_id: nil,
      seen_terminal: false,
      # pid => monitor ref; empty means "not subscriber-tracked" (never auto-stops)
      subscribers: monitor_subscriber(%{}, Keyword.get(opts, :subscriber)),
      backoff: initial,
      backoff_initial: initial,
      backoff_max: Keyword.get(opts, :backoff_max, 30_000)
    }

    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    open_opts = Keyword.put(state.source_opts, :last_event_id, state.last_event_id)

    case state.source.open(state.vm_id, open_opts) do
      {:ok, handle} ->
        {:noreply,
         %{
           state
           | handle: handle,
             buffer: "",
             seen_terminal: false,
             backoff: state.backoff_initial
         }}

      {:error, %Error{code: code} = error} when code in @permanent_codes ->
        Logger.info("fuse SSE #{state.vm_id} stopping: #{code}")
        broadcast(state, {:environment_stream_down, state.vm_id, error})
        {:stop, :normal, state}

      {:error, error} ->
        Logger.warning("fuse SSE #{state.vm_id} open failed: #{inspect(error)}")
        {:noreply, reconnect(state)}
    end
  end

  @impl true
  def handle_cast({:add_subscriber, pid}, state) do
    {:noreply, %{state | subscribers: monitor_subscriber(state.subscribers, pid)}}
  end

  @impl true
  def handle_info(:reconnect, state), do: {:noreply, state, {:continue, :connect}}

  # A monitored subscriber (e.g. a LiveView) went away. Drop it; when the last one
  # leaves, stop — so closing one viewer never tears down the stream for others,
  # and an abandoned stream doesn't linger. (Untracked consumers never get here.)
  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{subscribers: subs} = state)
      when is_map_key(subs, pid) do
    subs = Map.delete(subs, pid)

    if map_size(subs) == 0 do
      {:stop, :normal, %{state | subscribers: subs}}
    else
      {:noreply, %{state | subscribers: subs}}
    end
  end

  # A DOWN we don't track (shouldn't happen, but never route it to the parser).
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state), do: {:noreply, state}

  # Stray messages while disconnected (between reconnects) belong to a dead socket.
  def handle_info(_message, %{handle: nil} = state), do: {:noreply, state}

  def handle_info(message, state) do
    case state.source.parse(state.handle, message) do
      {:ok, chunks} ->
        handle_chunks(chunks, state)

      :unknown ->
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("fuse SSE #{state.vm_id} stream error: #{inspect(reason)}")
        {:noreply, reconnect(state)}
    end
  end

  @impl true
  def terminate(_reason, %{handle: handle, source: source}) when not is_nil(handle) do
    source.close(handle)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  # --- chunk handling ---

  defp handle_chunks(chunks, state) do
    Enum.reduce_while(chunks, {:noreply, state}, fn chunk, {:noreply, st} ->
      case handle_chunk(chunk, st) do
        {:cont, st2} -> {:cont, {:noreply, st2}}
        {:stop, st2} -> {:halt, {:stop, :normal, st2}}
        {:reconnect, st2} -> {:halt, {:noreply, reconnect(st2)}}
      end
    end)
  end

  defp handle_chunk({:data, bytes}, state) do
    {payloads, rest} = SSE.parse(state.buffer <> bytes)
    process_payloads(payloads, %{state | buffer: rest})
  end

  # Clean EOF. If we already saw a terminal event we'd have stopped; reaching
  # here means the stream ended unexpectedly, so reconnect.
  defp handle_chunk(:done, state) do
    if state.seen_terminal, do: {:stop, state}, else: {:reconnect, state}
  end

  defp handle_chunk({:trailers, _trailers}, state), do: {:cont, state}

  defp process_payloads(payloads, state) do
    Enum.reduce_while(payloads, {:cont, state}, fn payload, {_, st} ->
      case decode(payload) do
        {:ok, event} ->
          broadcast(st, {:environment_event, event})
          st = %{st | last_event_id: event.id || st.last_event_id}

          if Event.terminal?(event) do
            {:halt, {:stop, %{st | seen_terminal: true}}}
          else
            {:cont, {:cont, st}}
          end

        :error ->
          {:cont, {:cont, st}}
      end
    end)
  end

  defp decode(payload) do
    case Jason.decode(payload) do
      {:ok, map} when is_map(map) ->
        {:ok, Event.from_wire(map)}

      _ ->
        Logger.warning("fuse SSE dropping undecodable frame: #{inspect(payload)}")
        :error
    end
  end

  # --- reconnect / broadcast ---

  defp reconnect(state) do
    if state.handle, do: state.source.close(state.handle)
    Process.send_after(self(), :reconnect, state.backoff)
    next = min(state.backoff * 2, state.backoff_max)
    %{state | handle: nil, buffer: "", backoff: next}
  end

  defp broadcast(state, message) do
    Phoenix.PubSub.broadcast(state.pubsub, "environments", message)
    Phoenix.PubSub.broadcast(state.pubsub, "environment:#{state.vm_id}", message)
  end

  defp monitor_subscriber(subscribers, nil), do: subscribers

  defp monitor_subscriber(subscribers, pid) when is_pid(pid) do
    if Map.has_key?(subscribers, pid) do
      subscribers
    else
      Map.put(subscribers, pid, Process.monitor(pid))
    end
  end
end
