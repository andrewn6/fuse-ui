defmodule Fuse.Admin do
  @moduledoc """
  Console admin credential context.

  fuse has no per-user accounts, so the browser console is gated by a single
  shared password the operator sets on first run. This context owns that one
  credential: whether it exists yet (`configured?/0`), creating it
  (`set_password/1`), and checking a presented password (`verify_password/1`).

  The credential lives in the local SQLite DB. `CONTROL_PLANE_TOKEN` is a
  separate concern: it stays the bearer token for the `/api/v1` surface.
  """

  import Ecto.Query, only: [from: 2]

  alias Fuse.Admin.Credential
  alias Fuse.Repo

  @doc "Whether an admin password has been set (first-run setup is complete)."
  @spec configured?() :: boolean()
  def configured? do
    Repo.exists?(Credential)
  end

  @doc """
  Set the admin password. Refuses if one already exists so a first-run-only
  setup screen can't be replayed to take over an already-configured console.
  """
  @spec set_password(String.t()) ::
          {:ok, Credential.t()} | {:error, Ecto.Changeset.t()} | {:error, :already_configured}
  def set_password(password) do
    if configured?() do
      {:error, :already_configured}
    else
      %Credential{}
      |> Credential.changeset(%{password: password})
      |> Repo.insert()
    end
  end

  @doc """
  Verify a presented password against the stored hash. Runs a dummy hash when
  no credential exists so timing doesn't leak whether setup has happened.
  """
  @spec verify_password(String.t()) :: boolean()
  def verify_password(password) when is_binary(password) do
    case Repo.one(from c in Credential, limit: 1) do
      %Credential{password_hash: hash} -> Bcrypt.verify_pass(password, hash)
      nil -> Bcrypt.no_user_verify()
    end
  end

  def verify_password(_password), do: false
end
