defmodule FuseWeb.PageController do
  use FuseWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
