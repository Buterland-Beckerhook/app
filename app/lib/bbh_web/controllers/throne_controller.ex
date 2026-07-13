defmodule BbhWeb.ThroneController do
  use BbhWeb, :controller
  import BbhWeb.ControllerHelpers

  def index(conn, params) do
    result = Bbh.Content.list_thrones(page_param(params), 1)
    render(conn, :index, page_title: "Throne", result: result)
  end
end
