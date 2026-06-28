defmodule Fuse.Bounds do
  @moduledoc """
  Policy limits on the resources an environment may request, enforced before a
  create is forwarded to fuse.

  Structural validation (types/presence) is `Fuse.ResourceSpec`'s job; the *caps*
  live here so a deployment can tune them without touching the struct. Each cap is
  read from config; an omitted/`nil` cap means "no limit" for that field.

      config :fuse, Fuse.Bounds,
        max_cpus: 16,
        max_ram_mb: 131_072,
        max_storage_gb: 2_048,
        max_runtime_seconds: 604_800

  `check/1` returns `:ok`, or `{:error, %Fuse.Error{code: "invalid_argument"}}`
  whose `details` map names every field that exceeded its cap — so a caller can
  surface all violations at once rather than one at a time.
  """

  alias Fuse.Error
  alias Fuse.ResourceSpec

  # {spec field, config cap key, wire label}
  @checks [
    {:cpus, :max_cpus, "cpus"},
    {:ram_mb, :max_ram_mb, "ram_mb"},
    {:storage_gb, :max_storage_gb, "storage_gb"},
    {:max_runtime_seconds, :max_runtime_seconds, "max_runtime_seconds"}
  ]

  @doc """
  Check a `%Fuse.ResourceSpec{}` against the configured caps.

  ## Examples

      iex> spec = Fuse.ResourceSpec.new!(%{cpus: 2, ram_mb: 2048, storage_gb: 20})
      iex> Fuse.Bounds.check(spec)
      :ok
  """
  @spec check(ResourceSpec.t()) :: :ok | {:error, Error.t()}
  def check(%ResourceSpec{} = spec) do
    case violations(spec) do
      [] -> :ok
      details -> {:error, error(details)}
    end
  end

  defp violations(spec) do
    for {field, cap_key, label} <- @checks,
        cap = cap(cap_key),
        value = Map.get(spec, field),
        is_integer(cap) and is_integer(value) and value > cap,
        do: {label, "exceeds the maximum of #{cap}"}
  end

  defp error(violations) do
    %Error{
      code: "invalid_argument",
      message: "resource request exceeds allowed bounds",
      details: Map.new(violations),
      status: nil
    }
  end

  defp cap(key) do
    :fuse
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(key)
  end
end
