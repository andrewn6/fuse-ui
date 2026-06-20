defmodule Fuse.Mirror.Listener do
  @moduledoc """
  Subscribes to every watched environment's event stream and patches the local
  read model (`Fuse.Mirror`) as events arrive.

  Always supervised; the actual write is gated inside `Fuse.Mirror`, so when the
  mirror is disabled this process still runs and receives events but does no DB
  work. It owns no state beyond its subscription.
  """

  use GenServer

  require Logger

  alias Fuse.EventStream
  alias Fuse.Mirror

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    EventStream.subscribe_all()
    {:ok, %{}}
  end

  @impl true
  def handle_info({:environment_event, event}, state) do
    Mirror.apply_event(event)
    {:noreply, state}
  end

  # ignore stream-down notices and anything else; the mirror only tracks events
  def handle_info(_msg, state), do: {:noreply, state}
end
