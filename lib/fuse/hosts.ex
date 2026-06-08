defmodule Fuse.Hosts do
  @moduledoc """
  Hosts context: register/list/get/cordon/uncordon/remove of fuse worker nodes.

  Calls go through `Fuse.Client`; raw wire maps are decoded into
  `Fuse.Hosts.Host` structs (with `capacity` vs `allocated`). Client-side
  problems surface as `%Fuse.Error{code: "invalid_argument"}` for a uniform
  error shape.
  """

  alias Fuse.Client
  alias Fuse.Error
  alias Fuse.Hosts.Host

  @type result(t) :: {:ok, t} | {:error, Error.t()}

  @doc """
  Register a host.

  Requires `:id`, `:url`, `:capacity`; optional `:token`, `:region`.
  `:capacity` is a map of `cpus` / `ram_mb` / `storage_gb` / `vm_count`.
  """
  @spec register(map()) :: result(Host.t())
  def register(attrs) when is_map(attrs) do
    with {:ok, params} <- build_register_params(attrs),
         {:ok, map} <- Client.register_host(params) do
      {:ok, Host.from_wire(map)}
    end
  end

  @doc "List all hosts (fuse's host listing takes no filters)."
  @spec list() :: result([Host.t()])
  def list do
    with {:ok, items} <- Client.list_hosts() do
      {:ok, Enum.map(items, &Host.from_wire/1)}
    end
  end

  @doc "Fetch a single host by id."
  @spec get(String.t()) :: result(Host.t())
  def get(id) do
    with {:ok, map} <- Client.get_host(id) do
      {:ok, Host.from_wire(map)}
    end
  end

  @doc "Cordon a host (stop scheduling new VMs onto it)."
  @spec cordon(String.t()) :: result(nil)
  def cordon(id), do: Client.cordon_host(id)

  @doc "Uncordon a host (return it to the schedulable pool)."
  @spec uncordon(String.t()) :: result(nil)
  def uncordon(id), do: Client.uncordon_host(id)

  @doc "Remove a host from the cluster."
  @spec remove(String.t()) :: result(nil)
  def remove(id), do: Client.remove_host(id)

  # --- internals ---

  defp build_register_params(attrs) do
    with {:ok, id} <- require_field(attrs, :id),
         {:ok, url} <- require_field(attrs, :url),
         {:ok, capacity} <- require_field(attrs, :capacity) do
      params =
        %{"id" => id, "url" => url, "capacity" => capacity}
        |> maybe_put("token", fetch(attrs, :token))
        |> maybe_put("region", fetch(attrs, :region))

      {:ok, params}
    end
  end

  defp require_field(attrs, key) do
    case fetch(attrs, key) do
      nil -> {:error, invalid_argument("#{key} is required")}
      value -> {:ok, value}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp invalid_argument(message) do
    %Error{code: "invalid_argument", message: message, details: nil, status: nil}
  end

  defp fetch(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
