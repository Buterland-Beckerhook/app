defmodule BbhWeb.PageContentController do
  use BbhWeb, :controller
  import BbhWeb.ControllerHelpers

  alias Bbh.Content

  @doc "Section overview: the dynamic list of top-level Verein pages (replaces the old tiles)."
  def verein(conn, _params) do
    render(conn, :verein, page_title: "Verein", menu_pages: Content.list_menu_pages())
  end

  @doc "A single nested page under /verein/*path, with breadcrumb + section sidebar."
  def verein_page(conn, %{"path" => segments}) do
    case Content.get_page_by_path(segments) do
      {page, ancestors} ->
        render(conn, :verein_page,
          page_title: page.title,
          page: page,
          ancestors: ancestors,
          section_links: Content.section_links(List.first(ancestors)),
          current_path: conn.request_path,
          blocks: Content.load_blocks(page),
          people: people_for(page.slug)
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
          blocks: blocks
        )

      nil ->
        not_found(conn)
    end
  end

  # Backward-compatible people injection for the Vorstand/Offiziere pages until
  # they are modelled with a `person_list` block.
  defp people_for("vorstand"), do: Bbh.Club.list_vorstand()
  defp people_for("offiziere"), do: Bbh.Club.list_offiziere()
  defp people_for(_slug), do: nil
end
