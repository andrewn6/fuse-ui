defmodule Fuse.Error do
  @moduledoc """
  A typed representation of fuse's error envelope.

  Fuse returns errors as `{"error": {"code": ..., "message": ..., "details": ...}}`.
  This module parses that envelope (string- or atom-keyed) into a struct, with
  fallbacks for transport-level / malformed responses so callers always get a
  `%Fuse.Error{}` to match on.
  """

  @type t :: %__MODULE__{
          code: String.t() | nil,
          message: String.t(),
          details: map() | nil,
          status: pos_integer() | nil
        }

  @enforce_keys [:message]
  defstruct code: nil, message: nil, details: nil, status: nil

  @doc """
  Parse a decoded fuse error body into a `%Fuse.Error{}`.

  Accepts the full envelope (`%{"error" => %{...}}`), a bare error map, and
  string- or atom-keyed maps. `status` is the HTTP status code, threaded through
  by the client.

  ## Examples

      iex> Fuse.Error.parse(%{"error" => %{"code" => "not_found", "message" => "missing"}}, 404)
      %Fuse.Error{code: "not_found", message: "missing", details: nil, status: 404}

      iex> Fuse.Error.parse(%{"code" => "bad", "message" => "nope", "details" => %{"field" => "cpus"}})
      %Fuse.Error{code: "bad", message: "nope", details: %{"field" => "cpus"}, status: nil}
  """
  @spec parse(term(), pos_integer() | nil) :: t()
  def parse(body, status \\ nil)

  def parse(%{"error" => %{} = error}, status), do: parse(error, status)
  def parse(%{error: %{} = error}, status), do: parse(error, status)

  def parse(%{} = error, status) do
    %__MODULE__{
      code: fetch(error, :code),
      message: fetch(error, :message) || "Unknown fuse error",
      details: fetch(error, :details),
      status: status
    }
  end

  def parse(_other, status) do
    %__MODULE__{
      code: nil,
      message: "Malformed or unexpected fuse error response",
      details: nil,
      status: status
    }
  end

  @doc """
  Build an error for a transport-level failure (no HTTP response received).
  """
  @spec transport(term()) :: t()
  def transport(reason) do
    %__MODULE__{
      code: "transport_error",
      message: "Failed to reach fuse: #{inspect(reason)}",
      details: %{reason: reason},
      status: nil
    }
  end

  defp fetch(map, key) do
    Map.get(map, Atom.to_string(key)) || Map.get(map, key)
  end
end
