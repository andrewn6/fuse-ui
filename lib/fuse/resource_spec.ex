defmodule Fuse.ResourceSpec do
  @moduledoc """
  Build and validate the resource shape fuse expects for an environment:
  `{cpus, ram_mb, storage_gb, region, max_runtime_seconds}`.

  Validation here is **structural only** — types and presence. Policy limits
  (max cpus a tenant may request, etc.) live in `Fuse.Bounds` so they can be
  tuned per-deployment without touching this struct.
  """

  @type t :: %__MODULE__{
          cpus: pos_integer(),
          ram_mb: pos_integer(),
          storage_gb: pos_integer(),
          region: String.t() | nil,
          max_runtime_seconds: pos_integer() | nil
        }

  @enforce_keys [:cpus, :ram_mb, :storage_gb]
  defstruct [:cpus, :ram_mb, :storage_gb, :region, :max_runtime_seconds]

  @fields [:cpus, :ram_mb, :storage_gb, :region, :max_runtime_seconds]

  @doc """
  Build a validated `%Fuse.ResourceSpec{}` from a map (atom- or string-keyed).

  Returns `{:ok, spec}` or `{:error, errors}` where `errors` is a keyword list
  of `{field, message}`.

  ## Examples

      iex> Fuse.ResourceSpec.new(%{cpus: 2, ram_mb: 2048, storage_gb: 20})
      {:ok, %Fuse.ResourceSpec{cpus: 2, ram_mb: 2048, storage_gb: 20, region: nil, max_runtime_seconds: nil}}

      iex> Fuse.ResourceSpec.new(%{"cpus" => 1, "ram_mb" => 512, "storage_gb" => 10, "region" => "us-east"})
      {:ok, %Fuse.ResourceSpec{cpus: 1, ram_mb: 512, storage_gb: 10, region: "us-east", max_runtime_seconds: nil}}

      iex> Fuse.ResourceSpec.new(%{ram_mb: 512, storage_gb: 10})
      {:error, [cpus: "is required"]}
  """
  @spec new(map()) :: {:ok, t()} | {:error, keyword(String.t())}
  def new(attrs) when is_map(attrs) do
    normalized = normalize(attrs)

    case validate(normalized) do
      [] -> {:ok, struct!(__MODULE__, normalized)}
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  def new(_other), do: {:error, [base: "must be a map of resource attributes"]}

  @doc """
  Like `new/1` but raises `ArgumentError` on invalid input. Handy for building
  known-good specs (e.g. `Fuse.Plan` presets).
  """
  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, spec} -> spec
      {:error, errors} -> raise ArgumentError, "invalid resource spec: #{inspect(errors)}"
    end
  end

  @doc """
  Encode a spec into the string-keyed map fuse expects on the wire,
  omitting `nil` optional fields.

  ## Examples

      iex> spec = Fuse.ResourceSpec.new!(%{cpus: 2, ram_mb: 2048, storage_gb: 20})
      iex> Fuse.ResourceSpec.to_wire(spec)
      %{"cpus" => 2, "ram_mb" => 2048, "storage_gb" => 20}
  """
  @spec to_wire(t()) :: map()
  def to_wire(%__MODULE__{} = spec) do
    %{
      "cpus" => spec.cpus,
      "ram_mb" => spec.ram_mb,
      "storage_gb" => spec.storage_gb
    }
    |> put_optional("region", spec.region)
    |> put_optional("max_runtime_seconds", spec.max_runtime_seconds)
  end

  @doc """
  Leniently decode a wire spec map (string- or atom-keyed) into a struct.

  Unlike `new/1`, this performs **no validation** — it is for decoding fuse's
  responses, where fields fuse considers zero/default may be omitted. Missing
  fields become `nil`.

  ## Examples

      iex> Fuse.ResourceSpec.from_wire(%{"cpus" => 2, "ram_mb" => 2048})
      %Fuse.ResourceSpec{cpus: 2, ram_mb: 2048, storage_gb: nil, region: nil, max_runtime_seconds: nil}
  """
  @spec from_wire(map()) :: t()
  def from_wire(attrs) when is_map(attrs) do
    struct(__MODULE__, for(field <- @fields, into: %{}, do: {field, fetch(attrs, field)}))
  end

  defp normalize(attrs) do
    for field <- @fields, into: %{}, do: {field, fetch(attrs, field)}
  end

  defp validate(attrs) do
    []
    |> require_pos_int(attrs, :cpus)
    |> require_pos_int(attrs, :ram_mb)
    |> require_pos_int(attrs, :storage_gb)
    |> optional_pos_int(attrs, :max_runtime_seconds)
    |> optional_region(attrs)
  end

  defp require_pos_int(errors, attrs, field) do
    case Map.get(attrs, field) do
      nil -> [{field, "is required"} | errors]
      v when is_integer(v) and v > 0 -> errors
      _ -> [{field, "must be a positive integer"} | errors]
    end
  end

  defp optional_pos_int(errors, attrs, field) do
    case Map.get(attrs, field) do
      nil -> errors
      v when is_integer(v) and v > 0 -> errors
      _ -> [{field, "must be a positive integer"} | errors]
    end
  end

  defp optional_region(errors, attrs) do
    case Map.get(attrs, :region) do
      nil -> errors
      v when is_binary(v) and v != "" -> errors
      _ -> [{:region, "must be a non-empty string"} | errors]
    end
  end

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp fetch(map, key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
