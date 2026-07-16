defmodule BbhWeb.ThroneController do
  use BbhWeb, :controller
  import BbhWeb.ControllerHelpers

  def index(conn, params) do
    result = Bbh.Content.list_thrones(page_param(params), 1)
    nav = Bbh.Content.list_throne_nav()
    render(conn, :index, page_title: "Throne", result: result, nav: nav)
  end
end
