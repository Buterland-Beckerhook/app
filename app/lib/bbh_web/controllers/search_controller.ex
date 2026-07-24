defmodule BbhWeb.SearchController do
  use BbhWeb, :controller
  import BbhWeb.ControllerHelpers

  def index(conn, params) do
    q = params |> Map.get("q", "") |> to_string() |> String.trim()
    result = Bbh.Search.search(q, page_param(params), 20)

    render(conn, :index, page_title: "Suche", q: q, result: result)
  end
end
