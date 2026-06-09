defmodule FuseWeb.API.ErrorJSON do
  @moduledoc """
  Renders `%Fuse.Error{}` structs as the API's JSON error envelope.
  """

  def error(%{error: %Fuse.Error{} = e}) do
    %{errors: %{code: e.code, message: e.message, details: e.details}}
  end
end
