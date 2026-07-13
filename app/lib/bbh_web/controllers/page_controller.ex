defmodule BbhWeb.PageController do
  use BbhWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
