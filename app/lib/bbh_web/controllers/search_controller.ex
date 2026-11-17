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
    page = page_param(params)
    result = Bbh.Search.search(q, page, 20)

    conn
    |> track_search(q, page, result)
    |> render(:index, page_title: "Suche", q: q, tag: nil, result: result)
  end

  # Hand the term to BbhWeb.Plugs.TrackPageView, which records it together with the
  # page view — so bots and skipped requests are filtered out the same way. Only the
  # first result page counts, or paging through results would count a search twice.
  defp track_search(conn, "", _page, _result), do: conn

  defp track_search(conn, q, 1, result),
    do: put_private(conn, :bbh_search, %{term: q, hits: result.total})

  defp track_search(conn, _q, _page, _result), do: conn
end
