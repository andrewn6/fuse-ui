defmodule Fuse.Plan do
  @moduledoc """
  Named size presets that expand to a `Fuse.ResourceSpec`.

  Presets cover the common cases (`tiny`/`small`/`medium`/`large`); callers
  may layer `:region` and `:max_runtime_seconds` overrides on top.
  """

  alias Fuse.ResourceSpec

  @presets %{
    "tiny" => %{cpus: 1, ram_mb: 512, storage_gb: 10},
    "small" => %{cpus: 1, ram_mb: 1024, storage_gb: 20},
    "medium" => %{cpus: 2, ram_mb: 2048, storage_gb: 40},
    "large" => %{cpus: 4, ram_mb: 8192, storage_gb: 80}
  }

  @names ~w(tiny small medium large)

  @type name :: String.t()

  @doc "All known plan names, ordered smallest to largest."
  @spec names() :: [name()]
  def names, do: @names

  @doc """
  The raw resource attributes for a preset (atom-keyed), or `nil` if unknown.

  ## Examples

      iex> Fuse.Plan.preset("small")
      %{cpus: 1, ram_mb: 1024, storage_gb: 20}

      iex> Fuse.Plan.preset("nope")
      nil
  """
  @spec preset(term()) :: map() | nil
  def preset(name) when is_binary(name), do: Map.get(@presets, name)
  def preset(name) when is_atom(name) and not is_nil(name), do: preset(Atom.to_string(name))
  def preset(_other), do: nil

  @doc """
  Build a `Fuse.ResourceSpec` for a named plan, optionally merging
  `:region` and `:max_runtime_seconds` overrides (atom- or string-keyed).

  Returns `{:error, :unknown_plan}` for an unknown name, or the
  `{:error, errors}` from `Fuse.ResourceSpec.new/1` if overrides are invalid.

  ## Examples

      iex> {:ok, spec} = Fuse.Plan.spec("small")
      iex> {spec.cpus, spec.ram_mb, spec.storage_gb}
      {1, 1024, 20}

      iex> {:ok, spec} = Fuse.Plan.spec("tiny", %{region: "us-east"})
      iex> spec.region
      "us-east"

      iex> Fuse.Plan.spec("gigantic")
      {:error, :unknown_plan}
  """
  @spec spec(term(), map()) ::
          {:ok, ResourceSpec.t()} | {:error, :unknown_plan | keyword(String.t())}
  def spec(name, overrides \\ %{})

  def spec(name, overrides) when is_map(overrides) do
    case preset(name) do
      nil -> {:error, :unknown_plan}
      base -> ResourceSpec.new(Map.merge(base, known_overrides(overrides)))
    end
  end

  @doc """
  Like `spec/2` but raises `ArgumentError` on an unknown plan or invalid
  overrides.
  """
  @spec spec!(term(), map()) :: ResourceSpec.t()
  def spec!(name, overrides \\ %{}) do
    case spec(name, overrides) do
      {:ok, spec} -> spec
      {:error, :unknown_plan} -> raise ArgumentError, "unknown plan: #{inspect(name)}"
      {:error, errors} -> raise ArgumentError, "invalid plan overrides: #{inspect(errors)}"
    end
  end

  # Pick only the override keys we allow, dropping anything nil/absent so the
  # preset's own values win when no override is supplied.
  defp known_overrides(overrides) do
    for key <- [:region, :max_runtime_seconds],
        value = fetch(overrides, key),
        not is_nil(value),
        into: %{},
        do: {key, value}
  end

  defp fetch(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
