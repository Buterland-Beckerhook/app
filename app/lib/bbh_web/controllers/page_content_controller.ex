defmodule BbhWeb.PageContentController do
  use BbhWeb, :controller
  import BbhWeb.ControllerHelpers

  alias Bbh.Content

  @doc "Section overview: the dynamic list of top-level Verein pages (replaces the old tiles)."
  def verein(conn, _params) do
    preview? = Bbh.Authz.can_preview?(conn.assigns[:current_scope], :pages)

    render(conn, :verein,
      page_title: "Verein",
      preview: preview?,
      menu_pages: Content.Pages.list_menu_pages(preview?)
    )
  end

  @doc "A single nested page under /verein/*path, with breadcrumb + section sidebar."
  def verein_page(conn, %{"path" => segments}) do
    preview? = Bbh.Authz.can_preview?(conn.assigns[:current_scope], :pages)

    case Content.Pages.get_page_by_path(segments, preview?) do
      {page, ancestors} ->
        conn
        |> maybe_noindex(page)
        |> render(:verein_page,
          page_title: page.title,
          page: page,
          preview: preview? and page.status != "published",
          ancestors: ancestors,
          section_links: Content.Pages.section_links(List.first(ancestors), preview?),
          current_path: conn.request_path,
          blocks: Content.load_blocks(page)
        )

      nil ->
        # The page may exist but was reached via a non-canonical path → 301.
        case Content.Pages.find_menu_page(List.last(segments)) do
          {_leaf, ancestors} ->
            conn
            |> put_status(:moved_permanently)
            |> redirect(to: Content.Pages.page_path(ancestors))
            |> halt()

          nil ->
            not_found(conn)
        end
    end
  end

  @doc "An unlisted page under /seite/:slug — outside the menu, reachable only via links."
  def unlisted(conn, %{"slug" => slug}) do
    preview? = Bbh.Authz.can_preview?(conn.assigns[:current_scope], :pages)

    case Content.Pages.get_unlisted_page(slug, preview?) do
      {page, blocks} ->
        conn
        |> maybe_noindex(page)
        |> render(:page,
          page_title: page.title,
          title: page.title,
          page: page,
          preview: preview? and page.status != "published",
          blocks: blocks
        )

      nil ->
        not_found(conn)
    end
  end

  def impressum(conn, _params), do: render_static(conn, "impressum", "Impressum")
  def datenschutz(conn, _params), do: render_static(conn, "datenschutz", "Datenschutz")

  defp render_static(conn, slug, title) do
    case Content.Pages.get_published_page(slug) do
      {page, blocks} ->
        conn
        |> maybe_noindex(page)
        |> render(:page,
          page_title: page.title || title,
          title: page.title || title,
          page: page,
          blocks: blocks
        )

      nil ->
        not_found(conn)
    end
  end

  # Per-page opt-out from search engines. The header also covers crawlers that
  # never parse the HTML, and needs no layout change.
  defp maybe_noindex(conn, %{noindex: true}),
    do: put_resp_header(conn, "x-robots-tag", "noindex, nofollow")

  defp maybe_noindex(conn, _page), do: conn
end
