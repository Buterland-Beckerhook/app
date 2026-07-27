defmodule BbhWeb.ArticleController do
  use BbhWeb, :controller
  import BbhWeb.ControllerHelpers

  def index(conn, params) do
    result =
      Bbh.Content.list_published_articles(page_param(params), 12,
        include_unpublished: editor?(conn)
      )

    render(conn, :index, page_title: "Aktuelles", result: result)
  end

  def show(conn, %{"year" => year, "slug" => slug}) do
    with y when not is_nil(y) <- parse_year(year),
         {article, preview} <- lookup_article(conn, slug, y) do
      render(conn, :show,
        page_title: article.title,
        article: article,
        blocks: Bbh.Content.load_blocks(article),
        preview: preview
      )
    else
      _ -> not_found(conn)
    end
  end

  # Published articles are public; a logged-in editor may additionally preview an
  # unpublished one (draft / scheduled / archived). The second element is the
  # preview flag, which the template surfaces as a banner.
  defp lookup_article(conn, slug, y) do
    case Bbh.Content.get_published_article(slug, y) do
      nil -> preview_article(conn, slug, y)
      article -> {article, false}
    end
  end

  defp preview_article(conn, slug, y) do
    with true <- editor?(conn),
         article when not is_nil(article) <- Bbh.Content.get_article_by_slug_year(slug, y) do
      {article, true}
    else
      _ -> nil
    end
  end

  defp editor?(conn),
    do: BbhWeb.Authz.can_preview?(conn.assigns[:current_scope], :articles)
end
