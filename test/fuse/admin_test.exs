defmodule Fuse.AdminTest do
  use Fuse.DataCase, async: true

  alias Fuse.Admin

  test "configured? is false until a password is set" do
    refute Admin.configured?()
    {:ok, _} = Admin.set_password("a-strong-password")
    assert Admin.configured?()
  end

  test "set_password stores a hash, not the plaintext" do
    assert {:ok, credential} = Admin.set_password("a-strong-password")
    assert is_binary(credential.password_hash)
    refute credential.password_hash == "a-strong-password"
  end

  test "verify_password checks against the stored hash" do
    {:ok, _} = Admin.set_password("a-strong-password")
    assert Admin.verify_password("a-strong-password")
    refute Admin.verify_password("wrong-password")
  end

  test "verify_password is false when nothing is configured" do
    refute Admin.verify_password("anything")
  end

  test "set_password rejects a short password" do
    assert {:error, changeset} = Admin.set_password("short")
    assert "should be at least 8 character(s)" in errors_on(changeset).password
  end

  test "set_password refuses to overwrite an existing credential" do
    {:ok, _} = Admin.set_password("first-password")
    assert {:error, :already_configured} = Admin.set_password("second-password")
    assert Admin.verify_password("first-password")
  end
end
