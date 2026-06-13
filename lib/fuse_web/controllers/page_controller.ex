defmodule FuseWeb.PageController do
  use FuseWeb, :controller

  def home(conn, _params) do
    # The console is the product; send the root to the environments dashboard.
    redirect(conn, to: ~p"/environments")
  end
end
