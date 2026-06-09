defmodule FuseWeb.API.FallbackController do
  @moduledoc """
  Translates `{:error, %Fuse.Error{}}` tuples returned from controller actions
  into JSON error responses rendered by `FuseWeb.API.ErrorJSON`.
  """
  use FuseWeb, :controller

  def call(conn, {:error, %Fuse.Error{} = err}) do
    status = err.status || code_to_status(err.code)

    conn
    |> put_status(status)
    |> put_view(json: FuseWeb.API.ErrorJSON)
    |> render(:error, error: err)
  end

  defp code_to_status("not_found"), do: 404
  defp code_to_status("conflict"), do: 409
  defp code_to_status("invalid_argument"), do: 422
  defp code_to_status("unauthorized"), do: 401
  defp code_to_status("forbidden"), do: 403
  defp code_to_status("unavailable"), do: 503
  defp code_to_status("internal"), do: 500
  defp code_to_status("transport_error"), do: 502
  defp code_to_status(_), do: 500
end
