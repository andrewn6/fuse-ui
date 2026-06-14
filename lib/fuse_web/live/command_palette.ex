defmodule FuseWeb.CommandPalette do
  @moduledoc """
  Wires the ⌘K command palette into every console LiveView via an `on_mount`
  hook. The palette UI (open/close, keyboard nav, rendering) is a client hook in
  `FuseWeb.Layouts.console/1`; this module answers its two server calls:

    * `palette_search` — up to #{8} environments matching the query (id or task),
      pushed back to the hook as a `palette_results` event.
    * `palette_exec` — run a chosen command. Today that's in-app navigation
      (guarded to local paths).
  """

  import Phoenix.LiveView, only: [attach_hook: 4, push_event: 3, push_navigate: 2]

  alias Fuse.Environments

  @result_limit 8

  def on_mount(:default, _params, _session, socket) do
    {:cont, attach_hook(socket, :command_palette, :handle_event, &handle_event/3)}
  end

  defp handle_event("palette_search", %{"query" => query}, socket) do
    {:halt, push_event(socket, "palette_results", %{results: search(query)})}
  end

  defp handle_event("palette_exec", %{"action" => "navigate", "to" => "/" <> _ = to}, socket) do
    {:halt, push_navigate(socket, to: to)}
  end

  # always own palette_* events so an unknown/non-local target can never fall
  # through to (and crash) the host LiveView, which has no such handler
  defp handle_event("palette_exec", _params, socket), do: {:halt, socket}
  defp handle_event("palette_search", _params, socket), do: {:halt, socket}

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp search(query) do
    case query |> to_string() |> String.trim() |> String.downcase() do
      "" ->
        []

      q ->
        case Environments.list() do
          {:ok, envs} ->
            envs
            |> Enum.filter(&matches?(&1, q))
            |> Enum.take(@result_limit)
            |> Enum.map(&%{id: &1.id, task_id: &1.task_id, state: &1.state})

          _ ->
            []
        end
    end
  end

  defp matches?(env, q), do: contains?(env.id, q) or contains?(env.task_id, q)

  defp contains?(nil, _q), do: false
  defp contains?(value, q), do: String.contains?(String.downcase(value), q)
end
