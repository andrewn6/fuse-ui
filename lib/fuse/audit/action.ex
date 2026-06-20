defmodule Fuse.Audit.Action do
  @moduledoc """
  Ecto schema for one row in the append-only audit log: a single mutating action,
  who did it, what it touched, when, and the outcome.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "audit_log" do
    field :action, :string
    field :resource_type, :string
    field :resource_id, :string
    field :actor, :string
    field :metadata, :map
    field :result, :string
    field :occurred_at, :utc_datetime_usec
  end

  @fields ~w(action resource_type resource_id actor metadata result occurred_at)a

  @doc false
  def changeset(action, attrs) do
    action
    |> cast(attrs, @fields)
    |> validate_required([:action, :resource_type, :occurred_at])
  end
end
