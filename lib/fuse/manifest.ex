defmodule Fuse.Manifest do
  @moduledoc """
  Encode/decode the `manifest_inline` field used when creating environments.

  Fuse expects `manifest_inline` to be a standard-base64-encoded JSON document
  (standard alphabet, with padding). An empty/omitted value tells fuse to use
  its default manifest, so callers typically only set this for custom manifests.
  """

  @doc """
  Encode a manifest (any JSON-serializable term) into the base64 string fuse
  expects on the wire.

  ## Examples

      iex> {:ok, encoded} = Fuse.Manifest.encode(%{"version" => "1"})
      iex> Fuse.Manifest.decode(encoded)
      {:ok, %{"version" => "1"}}
  """
  @spec encode(term()) :: {:ok, String.t()} | {:error, term()}
  def encode(manifest) do
    case Jason.encode(manifest) do
      {:ok, json} -> {:ok, Base.encode64(json)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Like `encode/1` but raises `ArgumentError` on failure."
  @spec encode!(term()) :: String.t()
  def encode!(manifest) do
    case encode(manifest) do
      {:ok, encoded} -> encoded
      {:error, reason} -> raise ArgumentError, "could not encode manifest: #{inspect(reason)}"
    end
  end

  @doc """
  Decode a base64 `manifest_inline` string back into its JSON term.

  Returns `{:error, :invalid_base64}` if the input is not valid base64, or
  `{:error, :invalid_json}` if the decoded bytes are not valid JSON.

  ## Examples

      iex> {:ok, encoded} = Fuse.Manifest.encode(%{"k" => "v"})
      iex> Fuse.Manifest.decode(encoded)
      {:ok, %{"k" => "v"}}

      iex> Fuse.Manifest.decode("not base64!!")
      {:error, :invalid_base64}
  """
  @spec decode(String.t()) :: {:ok, term()} | {:error, :invalid_base64 | :invalid_json}
  def decode(encoded) when is_binary(encoded) do
    case Base.decode64(encoded) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, term} -> {:ok, term}
          {:error, _reason} -> {:error, :invalid_json}
        end

      :error ->
        {:error, :invalid_base64}
    end
  end

  @doc "Like `decode/1` but raises `ArgumentError` on failure."
  @spec decode!(String.t()) :: term()
  def decode!(encoded) do
    case decode(encoded) do
      {:ok, term} -> term
      {:error, reason} -> raise ArgumentError, "could not decode manifest: #{inspect(reason)}"
    end
  end
end
