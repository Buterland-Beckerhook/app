defmodule BbhWeb.NotFoundController do
  @moduledoc """
  Target of the router's final catch-all (`get "/*path"`): any GET no other route
  claimed. Hands over to `BbhWeb.Redirector`, so an old URL can still be redirected
  and a genuine miss lands in the 404 log.
  """
  use BbhWeb, :controller

  def show(conn, _params), do: BbhWeb.Redirector.not_found(conn)
end
