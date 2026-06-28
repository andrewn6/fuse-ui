defmodule FuseWeb.SetupController do
  @moduledoc """
  First-run setup: the operator creates the console admin password. This screen
  only exists while no credential is configured; once one is set it refuses to
  run again (so it can't be replayed to take over an existing console) and
  hands off to the normal login.

  On success the new session is marked authenticated and sent to the root, which
  routes on to host onboarding when the fleet is empty.
  """
  use FuseWeb, :controller

  alias Fuse.Admin
  alias FuseWeb.Auth

  def new(conn, _params) do
    cond do
      not Auth.enforce?() -> redirect(conn, to: ~p"/environments")
      Auth.configured?() -> redirect(conn, to: ~p"/login")
      true -> render_form(conn, nil)
    end
  end

  def create(conn, params) do
    password = params["password"] || ""
    confirmation = params["password_confirmation"] || ""

    cond do
      not Auth.enforce?() ->
        redirect(conn, to: ~p"/environments")

      Auth.configured?() ->
        redirect(conn, to: ~p"/login")

      password != confirmation ->
        render_form(conn, "Passwords do not match.")

      true ->
        case Admin.set_password(password) do
          {:ok, _credential} ->
            conn
            |> renew_session()
            |> put_session(:fuse_authenticated, true)
            |> redirect(to: ~p"/")

          {:error, %Ecto.Changeset{} = changeset} ->
            render_form(conn, changeset_error(changeset))

          {:error, :already_configured} ->
            redirect(conn, to: ~p"/login")
        end
    end
  end

  defp render_form(conn, error) do
    conn
    |> then(fn conn -> if error, do: put_status(conn, :bad_request), else: conn end)
    |> render(:new, error: error, page_title: "Set up Fuse")
  end

  # surface the first validation message (e.g. password length) for the form
  defp changeset_error(changeset) do
    case changeset.errors do
      [{:password, {message, opts}} | _] ->
        "Password " <> interpolate(message, opts)

      _ ->
        "Could not set the password. Please try again."
    end
  end

  defp interpolate(message, opts) do
    Enum.reduce(opts, message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end

  # renew the session id to prevent fixation, dropping any prior contents
  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
