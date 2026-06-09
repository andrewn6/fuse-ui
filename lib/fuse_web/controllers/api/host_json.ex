defmodule FuseWeb.API.HostJSON do
  @moduledoc """
  Serializes `Fuse.Hosts.Host` structs (with nested `Capacity`) into the API's
  snake_case JSON envelope. Timestamps render as ISO-8601; `nil` stays `null`.
  """

  alias Fuse.Hosts.Host

  @doc "Renders a list of hosts."
  def index(%{hosts: hosts}) do
    %{data: Enum.map(hosts, &data/1)}
  end

  @doc "Renders a single host."
  def show(%{host: host}) do
    %{data: data(host)}
  end

  @doc "Serializes a single `Host` struct."
  def data(%Host{} = host) do
    %{
      id: host.id,
      url: host.url,
      region: host.region,
      state: host.state,
      capacity: capacity(host.capacity),
      allocated: capacity(host.allocated),
      last_seen: datetime(host.last_seen),
      created_at: datetime(host.created_at),
      updated_at: datetime(host.updated_at)
    }
  end

  defp capacity(%Host.Capacity{} = cap) do
    %{
      cpus: cap.cpus,
      ram_mb: cap.ram_mb,
      storage_gb: cap.storage_gb,
      vm_count: cap.vm_count
    }
  end

  defp capacity(nil), do: nil

  defp datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp datetime(nil), do: nil
end
