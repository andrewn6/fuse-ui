defmodule Fuse.Health do
  @moduledoc """
  Reachability of the fuse control plane, via its unauthenticated probes.

      :ok          # 200 — fuse answered the probe
      :degraded    # 503 — reachable, but a fuse dependency is unhealthy
      :unreachable # transport error — fuse can't be reached at all

  Two probes, mirroring fuse's own split:

    * `check/0` (alias `readiness/0`) hits `/ready` — is fuse ready to serve?
      503 means up-but-not-ready (`:degraded`).
    * `liveness/0` hits `/health` — is the fuse process alive at all?
  """

  alias Fuse.Client
  alias Fuse.Error

  @type status :: :ok | :degraded | :unreachable

  @doc "Probe fuse's readiness endpoint (`/ready`) and collapse it to a status."
  @spec check() :: status()
  def check, do: collapse(Client.ready())

  @doc "Alias for `check/0` — fuse's readiness (`/ready`)."
  @spec readiness() :: status()
  def readiness, do: check()

  @doc "Probe fuse's liveness endpoint (`/health`) and collapse it to a status."
  @spec liveness() :: status()
  def liveness, do: collapse(Client.health())

  defp collapse({:ok, _}), do: :ok
  defp collapse({:error, %Error{status: 503}}), do: :degraded
  defp collapse({:error, _}), do: :unreachable
end
