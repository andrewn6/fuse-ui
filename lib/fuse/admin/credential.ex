defmodule Fuse.Admin.Credential do
  @moduledoc """
  The console admin credential: a single bcrypt password hash.

  fuse has no per-user accounts, so the browser console is gated by one shared
  password set on first run. The plaintext `password` is a virtual field cast
  through the changeset and hashed into `password_hash`; the plaintext is never
  persisted (and is redacted from inspect output).
  """
  use Ecto.Schema
  import Ecto.Changeset

  # bcrypt only considers the first 72 bytes of a password; reject longer ones
  # rather than silently truncating.
  @min_length 8
  @max_length 72

  schema "console_credentials" do
    field :password_hash, :string
    field :password, :string, virtual: true, redact: true

    timestamps(type: :utc_datetime)
  end

  @doc "Cast and hash a new admin password."
  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_length(:password, min: @min_length, max: @max_length)
    |> put_password_hash()
  end

  defp put_password_hash(
         %Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset
       ) do
    changeset
    |> put_change(:password_hash, Bcrypt.hash_pwd_salt(password))
    |> delete_change(:password)
  end

  defp put_password_hash(changeset), do: changeset
end
