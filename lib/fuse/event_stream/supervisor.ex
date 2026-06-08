defmodule Fuse.EventStream.Supervisor do
  @moduledoc """
  `DynamicSupervisor` for per-environment `Fuse.EventStream.Consumer` processes.

  Consumers are started/stopped on demand through `Fuse.EventStream.watch/2` and
  `unwatch/1`; uniqueness per `vm_id` is enforced via `Fuse.EventStream.Registry`.
  """

  use DynamicSupervisor

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
