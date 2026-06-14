defmodule FuseWeb.Connection do
  @moduledoc """
  `on_mount` hook giving every console LiveView a live view of fuse reachability.

  Assigns `:connection` (`:checking | :ok | :degraded | :unreachable`). On a
  connected mount it polls `Fuse.Health.check/0` every 15s via an attached
  `handle_info`. The first check is *scheduled*, not run inline, so mount stays
  fast even when fuse is slow or down.
  """
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]
  import Phoenix.Component, only: [assign: 3]

  alias Fuse.Health

  @interval 15_000

  def on_mount(:default, _params, _session, socket) do
    socket = assign(socket, :connection, :checking)

    socket =
      if connected?(socket) do
        send(self(), :check_connection)
        attach_hook(socket, :fuse_connection, :handle_info, &handle_info/2)
      else
        socket
      end

    {:cont, socket}
  end

  defp handle_info(:check_connection, socket) do
    Process.send_after(self(), :check_connection, @interval)
    {:halt, assign(socket, :connection, Health.check())}
  end

  defp handle_info(_message, socket), do: {:cont, socket}
end
