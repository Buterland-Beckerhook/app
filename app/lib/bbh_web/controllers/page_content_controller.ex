defmodule BbhWeb.PageContentController do
  use BbhWeb, :controller
  import BbhWeb.ControllerHelpers

  alias Bbh.Content

  @doc "Section overview: the dynamic list of top-level Verein pages (replaces the old tiles)."
  def verein(conn, _params) do
    preview? = BbhWeb.Authz.can_preview?(conn.assigns[:current_scope], :pages)

    render(conn, :verein,
      page_title: "Verein",
      preview: preview?,
      menu_pages: Content.list_menu_pages(preview?)
    )
  end

  @doc "A single nested page under /verein/*path, with breadcrumb + section sidebar."
  def verein_page(conn, %{"path" => segments}) do
    preview? = BbhWeb.Authz.can_preview?(conn.assigns[:current_scope], :pages)

    case Content.get_page_by_path(segments, preview?) do
      {page, ancestors} ->
        render(conn, :verein_page,
          page_title: page.title,
          page: page,
          preview: preview? and page.status != "published",
          ancestors: ancestors,
          section_links: Content.section_links(List.first(ancestors), preview?),
          current_path: conn.request_path,
          blocks: Content.load_blocks(page)
        )

      nil ->
        # The page may exist but was reached via a non-canonical path → 301.
        case Content.find_menu_page(List.last(segments)) do
          {_leaf, ancestors} ->
            conn
            |> put_status(:moved_permanently)
            |> redirect(to: Content.page_path(ancestors))
            |> halt()

          nil ->
            not_found(conn)
        end
    end
  end

  def impressum(conn, _params), do: render_static(conn, "impressum", "Impressum")
  def datenschutz(conn, _params), do: render_static(conn, "datenschutz", "Datenschutz")

  defp render_static(conn, slug, title) do
    case Content.get_published_page(slug) do
      {page, blocks} ->
        render(conn, :page,
          page_title: page.title || title,
          title: page.title || title,
          page: page,
          blocks: blocks
        )

      nil ->
        not_found(conn)
    end
  end
end
