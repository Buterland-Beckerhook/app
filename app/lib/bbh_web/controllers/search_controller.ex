defmodule BbhWeb.SearchController do
  use BbhWeb, :controller
  import BbhWeb.ControllerHelpers

  # `?tag=` is where the tag links on articles lead: an exact listing of the articles
  # carrying that tag, not a full-text search (which would stem it and match the copy).
  def index(conn, %{"tag" => tag} = params) when is_binary(tag) and tag != "" do
    tag = String.trim(tag)
    result = Bbh.Content.list_published_articles(page_param(params), 18, tag: tag)

    render(conn, :index, page_title: "Schlagwort „#{tag}“", q: "", tag: tag, result: result)
  end

  def index(conn, params) do
    q = params |> Map.get("q", "") |> to_string() |> String.trim()
    result = Bbh.Search.search(q, page_param(params), 20)

    render(conn, :index, page_title: "Suche", q: q, tag: nil, result: result)
  end
end
