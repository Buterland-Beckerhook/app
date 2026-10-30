defmodule BbhWeb.SitemapController do
  use BbhWeb, :controller
  alias Bbh.Content

  @static ~w(/ /aktuell /termine /thron /verein /kontakt)
  @legal ~w(impressum datenschutz)

  # sobelow_skip ["XSS.SendResp"]
  # Served as application/xml; every interpolated value is escaped in url_element/1.
  def index(conn, _params) do
    base = Application.get_env(:bbh, :site_url, "https://buterland-beckerhook.de")

    entries =
      Enum.map(@static, &{base <> &1, nil}) ++
        legal_entries(base) ++
        throne_entries(base) ++
        article_entries(base) ++
        event_entries(base) ++
        page_entries(base) ++
        unlisted_entries(base)

    body = """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    #{Enum.map_join(entries, "\n", &url_element/1)}
    </urlset>
    """

    conn |> put_resp_content_type("application/xml") |> send_resp(200, body)
  end

  # Per-type throne list pages, only for types that actually have records.
  # /thron (König) is already covered by @static.
  defp throne_entries(base) do
    %{types_present: types} = Content.throne_menu()

    for type <- ["stadtkaiser", "jungschuetzenkoenig"], MapSet.member?(types, type) do
      {"#{base}/thron/#{type}", nil}
    end
  end

  defp article_entries(base) do
    for {year, slug, modified} <- Content.list_published_article_refs(),
        do: {"#{base}/aktuell/#{year}/#{slug}", modified}
  end

  defp event_entries(base) do
    for {year, slug, updated} <- Bbh.Calendar.list_public_event_refs(),
        do: {"#{base}/termine/#{year}/#{slug}", updated}
  end

  # Impressum/Datenschutz, unless an editor opted them out of indexing.
  defp legal_entries(base) do
    indexable = Content.indexable_page_slugs(@legal)
    for slug <- @legal, slug in indexable, do: {"#{base}/#{slug}", nil}
  end

  # Published, indexable pages reachable under /verein: whole ancestor chain
  # published and rooted at a menu page — exactly the published menu tree.
  defp page_entries(base) do
    for {page, path, _depth} <- Content.menu_page_tree(),
        not page.noindex,
        do: {base <> path, page.updated_at}
  end

  # Unlisted pages are link-only, not secret: they are listed unless marked noindex.
  defp unlisted_entries(base) do
    Content.list_unlisted_pages()
    |> Enum.reject(& &1.noindex)
    |> Enum.map(&{"#{base}/seite/#{&1.slug}", &1.updated_at})
  end

  # Locations contain editor-chosen slugs, so they are XML-escaped: an unescaped `&`
  # breaks the document, and markup would be live in a browser (XHTML namespace).
  defp url_element({loc, nil}), do: "  <url><loc>#{xml_escape(loc)}</loc></url>"

  defp url_element({loc, %DateTime{} = dt}) do
    "  <url><loc>#{xml_escape(loc)}</loc><lastmod>#{DateTime.to_date(dt)}</lastmod></url>"
  end

  defp xml_escape(text), do: text |> Plug.HTML.html_escape_to_iodata() |> IO.iodata_to_binary()
end
