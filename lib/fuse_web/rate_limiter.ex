defmodule FuseWeb.RateLimiter do
  @moduledoc """
  Fixed-window request counting, backed by a single public ETS table.

  A supervised process owns the table (so it survives individual requests) and
  periodically prunes windows that have rolled over. The counting itself happens
  in the caller (the plug) via `hit/3`, which is a couple of lock-free ETS ops.

  This is the mechanism; the policy (limit, window, which routes) lives in
  `FuseWeb.Plugs.RateLimiter`.
  """

  use GenServer

  @table __MODULE__

  @doc "Start the table owner. Added to the app supervision tree."
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Record one request for `key` in the current `window_ms` window and report
  whether it is still within `limit`.

  Returns `{:allow, count}` or `{:deny, count}` where `count` is the running
  total for this window. The window is derived from the system clock, so callers
  in the same window share a counter without coordinating.
  """
  @spec hit(term(), pos_integer(), pos_integer()) ::
          {:allow, pos_integer()} | {:deny, pos_integer()}
  def hit(key, limit, window_ms) do
    window = div(System.system_time(:millisecond), window_ms)
    count = :ets.update_counter(@table, {key, window}, {2, 1}, {{key, window}, 0})
    if count > limit, do: {:deny, count}, else: {:allow, count}
  end

  @doc false
  # test helper: drop all counters so cases don't bleed into each other
  def reset, do: :ets.delete_all_objects(@table)

  @impl true
  def init(opts) do
    :ets.new(@table, [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, %{window_ms: opts[:window_ms] || 60_000}, prune_interval(opts)}
  end

  @impl true
  def handle_info(:timeout, state) do
    prune(state.window_ms)
    {:noreply, state, prune_interval([])}
  end

  # drop entries whose window is older than the current one; cheap match_delete.
  defp prune(window_ms) do
    current = div(System.system_time(:millisecond), window_ms)
    :ets.select_delete(@table, [{{{:_, :"$1"}, :_}, [{:<, :"$1", current}], [true]}])
  end

  defp prune_interval(opts), do: opts[:window_ms] || 60_000
end
