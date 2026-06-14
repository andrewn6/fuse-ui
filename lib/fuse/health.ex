defmodule Fuse.Health do
  @moduledoc """
  Reachability of the fuse control plane, via its unauthenticated `/ready` probe.

      :ok          # 200 — fuse is reachable and ready
      :degraded    # 503 — reachable, but a fuse dependency is unhealthy
      :unreachable # transport error — fuse can't be reached at all
  """

  alias Fuse.Client
  alias Fuse.Error

  @type status :: :ok | :degraded | :unreachable

  @doc "Probe fuse's readiness endpoint and collapse the result to a status atom."
  @spec check() :: status()
  def check do
    case Client.ready() do
      {:ok, _} -> :ok
      {:error, %Error{status: 503}} -> :degraded
      {:error, _} -> :unreachable
    end
  end
end
