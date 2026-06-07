defmodule Fuse.SnapshotState do
  @moduledoc """
  Snapshot lifecycle states (and nested export states), mirroring fuse.

  Snapshot states: `creating`, `ready`, `restoring`, `deleting`, `error`.
  A snapshot is only safe to restore/export from when `ready`. Each export
  attached to a snapshot carries its own status: `pending`, `ready`, `error`.
  All values are the lowercase strings fuse uses on the wire.
  """

  @states ~w(creating ready restoring deleting error)
  @in_progress ~w(creating restoring deleting)
  @export_states ~w(pending ready error)

  @type t :: String.t()

  @doc "All known snapshot states."
  @spec states() :: [t()]
  def states, do: @states

  @doc "All known snapshot export states."
  @spec export_states() :: [t()]
  def export_states, do: @export_states

  @doc """
  Normalize a value (string or atom) to a known snapshot state string.

  ## Examples

      iex> Fuse.SnapshotState.cast("ready")
      {:ok, "ready"}

      iex> Fuse.SnapshotState.cast(:creating)
      {:ok, "creating"}

      iex> Fuse.SnapshotState.cast("nope")
      :error
  """
  @spec cast(term()) :: {:ok, t()} | :error
  def cast(state) when is_atom(state) and not is_nil(state), do: cast(Atom.to_string(state))

  def cast(state) when is_binary(state) do
    if state in @states, do: {:ok, state}, else: :error
  end

  def cast(_other), do: :error

  @doc "Whether the given value is a known snapshot state."
  @spec valid?(term()) :: boolean()
  def valid?(state), do: match?({:ok, _}, cast(state))

  @doc "Whether the snapshot is `ready` (safe to restore or export from)."
  @spec ready?(term()) :: boolean()
  def ready?(state), do: cast(state) == {:ok, "ready"}

  @doc "Whether the snapshot is in the `error` state."
  @spec error?(term()) :: boolean()
  def error?(state), do: cast(state) == {:ok, "error"}

  @doc "Whether an operation is in flight (`creating`, `restoring`, or `deleting`)."
  @spec in_progress?(term()) :: boolean()
  def in_progress?(state) do
    case cast(state) do
      {:ok, s} -> s in @in_progress
      :error -> false
    end
  end

  @doc "Whether the given value is a known export status."
  @spec export_valid?(term()) :: boolean()
  def export_valid?(status) when is_atom(status) and not is_nil(status),
    do: export_valid?(Atom.to_string(status))

  def export_valid?(status) when is_binary(status), do: status in @export_states
  def export_valid?(_other), do: false

  @doc "Whether an export is `ready` (downloadable)."
  @spec export_ready?(term()) :: boolean()
  def export_ready?(status) when is_atom(status) and not is_nil(status),
    do: export_ready?(Atom.to_string(status))

  def export_ready?(status), do: status == "ready"
end
