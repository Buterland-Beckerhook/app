defmodule BbhWeb.SitemapController do
  use BbhWeb, :controller
  import Ecto.Query
  alias Bbh.Content
  alias Bbh.Repo
  alias Bbh.Content.{Article, Page}
  alias Bbh.Calendar.Event

  @static ~w(/ /aktuell /termine /thron /verein /kontakt /impressum /datenschutz)

  def index(conn, _params) do
    base = Application.get_env(:bbh, :site_url, "https://buterland-beckerhook.de")

    entries =
      Enum.map(@static, &{base <> &1, nil}) ++
        throne_entries(base) ++
        article_entries(base) ++
        event_entries(base) ++
        page_entries(base)

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
    Repo.all(
      from a in Article,
        where: a.status == "published" and a.no_article == false,
        select: {a.year, a.slug, a.date_modified, a.date_published}
    )
    |> Enum.map(fn {year, slug, modified, published} ->
      {"#{base}/aktuell/#{year}/#{slug}", modified || published}
    end)
  end

  defp event_entries(base) do
    Repo.all(
      from e in Event,
        where: e.status == "published" and e.announce == true and is_nil(e.calendar),
        select: {e.year, e.slug, e.updated_at}
    )
    |> Enum.map(fn {year, slug, updated} -> {"#{base}/termine/#{year}/#{slug}", updated} end)
  end

  # Published pages reachable under /verein: whole ancestor chain published and
  # rooted at a menu page (legal pages are covered by @static).
  defp page_entries(base) do
    Repo.all(from p in Page, where: p.status == "published")
    |> Enum.flat_map(fn page ->
      ancestors = Content.page_ancestors(page)

      if match?(%Page{show_in_menu: true}, List.first(ancestors)) and
           Enum.all?(ancestors, &(&1.status == "published")) do
        [{base <> Content.page_path(ancestors), page.updated_at}]
      else
        []
      end
    end)
  end

  defp url_element({loc, nil}), do: "  <url><loc>#{loc}</loc></url>"

  defp url_element({loc, %DateTime{} = dt}) do
    "  <url><loc>#{loc}</loc><lastmod>#{DateTime.to_date(dt)}</lastmod></url>"
  end
end
