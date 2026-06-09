defmodule FuseWeb.API.EnvironmentJSON do
  @moduledoc """
  Renders `Fuse.Environments.Environment` structs as the API's JSON envelope.
  """

  alias Fuse.Environments.Environment
  alias Fuse.ResourceSpec

  @doc "Renders a list of environments."
  def index(%{environments: environments}) do
    %{data: Enum.map(environments, &data/1)}
  end

  @doc "Renders a single environment."
  def show(%{environment: environment}) do
    %{data: data(environment)}
  end

  @doc "Serializes an `Environment` into a string/atom-keyed map."
  def data(%Environment{} = environment) do
    %{
      id: environment.id,
      state: environment.state,
      task_id: environment.task_id,
      host_id: environment.host_id,
      url: environment.url,
      spec: spec(environment.spec),
      error: environment.error,
      created_at: datetime(environment.created_at),
      updated_at: datetime(environment.updated_at)
    }
  end

  defp spec(%ResourceSpec{} = spec) do
    %{
      cpus: spec.cpus,
      ram_mb: spec.ram_mb,
      storage_gb: spec.storage_gb,
      region: spec.region,
      max_runtime_seconds: spec.max_runtime_seconds
    }
  end

  defp spec(nil), do: nil

  defp datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp datetime(nil), do: nil
end
