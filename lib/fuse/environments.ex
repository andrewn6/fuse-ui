defmodule Fuse.Environments do
  @moduledoc """
  Environments context: list/get/create/drain/rotate_token/destroy of fuse
  microVM environments.

  Calls go through `Fuse.Client` (HTTP in prod, the in-memory fake in tests);
  raw wire maps are decoded into `Fuse.Environments.Environment` structs.
  `create/1` validates and encodes its input before hitting fuse, surfacing
  client-side problems as `%Fuse.Error{code: "invalid_argument"}` so callers
  always match on a single error shape.
  """

  alias Fuse.Bounds
  alias Fuse.Client
  alias Fuse.Environments.Environment
  alias Fuse.Error
  alias Fuse.Manifest
  alias Fuse.ResourceSpec

  @type result(t) :: {:ok, t} | {:error, Error.t()}

  @doc """
  List environments, optionally filtered by `:task_id`, `:state`, `:host_id`.
  """
  @spec list(map()) :: result([Environment.t()])
  def list(filters \\ %{}) do
    with {:ok, items} <- Client.list_environments(filters) do
      {:ok, Enum.map(items, &Environment.from_wire/1)}
    end
  end

  @doc "Fetch a single environment by id."
  @spec get(String.t()) :: result(Environment.t())
  def get(id) do
    with {:ok, map} <- Client.get_environment(id) do
      {:ok, Environment.from_wire(map)}
    end
  end

  @doc """
  Create an environment.

  Accepts:

    * `:task_id` (required)
    * `:spec` (required) — a `%Fuse.ResourceSpec{}` or an attrs map
    * `:manifest` (optional) — any JSON-able term, encoded to `manifest_inline`,
      or `:manifest_inline` for an already-base64-encoded value
    * `:secrets`, `:startup_script`, `:gateway_url`, `:gateway_token` (optional)
  """
  @spec create(map()) :: result(Environment.t())
  def create(attrs) when is_map(attrs) do
    with {:ok, params} <- build_create_params(attrs),
         {:ok, map} <- Client.create_environment(params) do
      {:ok, Environment.from_wire(map)}
    end
  end

  @doc "Drain an environment (graceful shutdown). Returns the updated environment."
  @spec drain(String.t()) :: result(Environment.t() | nil)
  def drain(id) do
    with {:ok, map} <- Client.drain_environment(id) do
      {:ok, decode_maybe(map)}
    end
  end

  @doc "Rotate the environment's guest token."
  @spec rotate_token(String.t()) :: result(nil)
  def rotate_token(id), do: Client.rotate_token(id)

  @doc "Destroy an environment."
  @spec destroy(String.t()) :: result(nil)
  def destroy(id), do: Client.destroy_environment(id)

  # --- internals ---

  defp build_create_params(attrs) do
    with {:ok, task_id} <- fetch_required(attrs, :task_id),
         {:ok, spec} <- build_spec(fetch(attrs, :spec)),
         :ok <- Bounds.check(spec),
         {:ok, manifest_inline} <- build_manifest(attrs) do
      params =
        %{"task_id" => task_id, "spec" => ResourceSpec.to_wire(spec)}
        |> maybe_put("manifest_inline", manifest_inline)
        |> maybe_put("secrets", fetch(attrs, :secrets))
        |> maybe_put("startup_script", fetch(attrs, :startup_script))
        |> maybe_put("gateway_url", fetch(attrs, :gateway_url))
        |> maybe_put("gateway_token", fetch(attrs, :gateway_token))

      {:ok, params}
    end
  end

  defp build_spec(%ResourceSpec{} = spec), do: {:ok, spec}

  defp build_spec(attrs) when is_map(attrs) do
    case ResourceSpec.new(attrs) do
      {:ok, spec} -> {:ok, spec}
      {:error, errors} -> {:error, invalid_argument("invalid spec", stringify_errors(errors))}
    end
  end

  defp build_spec(nil), do: {:error, invalid_argument("spec is required")}

  defp build_spec(_other),
    do: {:error, invalid_argument("spec must be a map or %Fuse.ResourceSpec{}")}

  defp build_manifest(attrs) do
    cond do
      inline = fetch(attrs, :manifest_inline) ->
        {:ok, inline}

      not is_nil(fetch(attrs, :manifest)) ->
        case Manifest.encode(fetch(attrs, :manifest)) do
          {:ok, encoded} ->
            {:ok, encoded}

          {:error, reason} ->
            {:error, invalid_argument("invalid manifest", %{"reason" => inspect(reason)})}
        end

      true ->
        {:ok, nil}
    end
  end

  defp fetch_required(attrs, key) do
    case fetch(attrs, key) do
      value when value in [nil, ""] -> {:error, invalid_argument("#{key} is required")}
      value -> {:ok, value}
    end
  end

  defp decode_maybe(nil), do: nil
  defp decode_maybe(map) when is_map(map), do: Environment.from_wire(map)

  defp invalid_argument(message, details \\ nil) do
    %Error{code: "invalid_argument", message: message, details: details, status: nil}
  end

  defp stringify_errors(errors), do: Map.new(errors, fn {key, msg} -> {to_string(key), msg} end)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp fetch(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
