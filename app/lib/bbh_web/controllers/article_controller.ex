defmodule BbhWeb.ArticleController do
  use BbhWeb, :controller
  import BbhWeb.ControllerHelpers

  def index(conn, params) do
    result = Bbh.Content.list_published_articles(page_param(params), 10)
    render(conn, :index, page_title: "Aktuelles", result: result)
  end

  def show(conn, %{"year" => year, "slug" => slug}) do
    with y when not is_nil(y) <- parse_year(year),
         article when not is_nil(article) <- Bbh.Content.get_published_article(slug, y) do
      render(conn, :show, page_title: article.title, article: article)
    else
      _ -> not_found(conn)
    end
  end
end
