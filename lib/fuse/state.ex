defmodule Fuse.State do
  @moduledoc """
  Environment lifecycle states and transition rules, mirroring fuse.

  Fuse stores four states (`provisioning`, `running`, `draining`,
  `destroying`) and emits two additional synthetic terminal states on the
  wire / SSE stream (`destroyed`, `failed`). All are represented here as the
  lowercase strings fuse uses on the wire.
  """

  @states ~w(provisioning running draining destroying destroyed failed)
  @terminal ~w(destroyed failed)

  # Legal forward transitions. Every non-terminal state may also jump straight
  # to a terminal state (destroyed/failed) via reconcile / error handling.
  @transitions %{
    "provisioning" => ~w(running draining destroying destroyed failed),
    "running" => ~w(draining destroying destroyed failed),
    "draining" => ~w(destroying destroyed failed),
    "destroying" => ~w(destroyed failed),
    "destroyed" => [],
    "failed" => []
  }

  @type t :: String.t()

  @doc "All known environment states."
  @spec states() :: [t()]
  def states, do: @states

  @doc "States that are terminal (no outgoing transitions)."
  @spec terminal_states() :: [t()]
  def terminal_states, do: @terminal

  @doc """
  Normalize a value (string or atom) to a known state string.

  ## Examples

      iex> Fuse.State.cast("running")
      {:ok, "running"}

      iex> Fuse.State.cast(:provisioning)
      {:ok, "provisioning"}

      iex> Fuse.State.cast("nope")
      :error
  """
  @spec cast(term()) :: {:ok, t()} | :error
  def cast(state) when is_atom(state) and not is_nil(state), do: cast(Atom.to_string(state))

  def cast(state) when is_binary(state) do
    if state in @states, do: {:ok, state}, else: :error
  end

  def cast(_other), do: :error

  @doc "Whether the given value is a known environment state."
  @spec valid?(term()) :: boolean()
  def valid?(state), do: match?({:ok, _}, cast(state))

  @doc "Whether the environment is in the `running` state."
  @spec running?(term()) :: boolean()
  def running?(state), do: cast(state) == {:ok, "running"}

  @doc "Whether the state is terminal (`destroyed` or `failed`)."
  @spec terminal?(term()) :: boolean()
  def terminal?(state) do
    case cast(state) do
      {:ok, s} -> s in @terminal
      :error -> false
    end
  end

  @doc "Whether the state is a known, non-terminal (still mutable) state."
  @spec active?(term()) :: boolean()
  def active?(state), do: valid?(state) and not terminal?(state)

  @doc """
  Allowed next states from the given state. Unknown states yield `[]`.

  ## Examples

      iex> Fuse.State.transitions("running")
      ["draining", "destroying", "destroyed", "failed"]

      iex> Fuse.State.transitions("destroyed")
      []
  """
  @spec transitions(term()) :: [t()]
  def transitions(state) do
    case cast(state) do
      {:ok, s} -> Map.fetch!(@transitions, s)
      :error -> []
    end
  end

  @doc """
  Whether a transition from `from` to `to` is legal.

  ## Examples

      iex> Fuse.State.can_transition?("running", "draining")
      true

      iex> Fuse.State.can_transition?("destroyed", "running")
      false
  """
  @spec can_transition?(term(), term()) :: boolean()
  def can_transition?(from, to) do
    case cast(to) do
      {:ok, to_state} -> to_state in transitions(from)
      :error -> false
    end
  end
end
