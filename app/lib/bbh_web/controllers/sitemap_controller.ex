defmodule BbhWeb.SitemapController do
  use BbhWeb, :controller
  import Ecto.Query
  alias Bbh.Repo
  alias Bbh.Content.Article
  alias Bbh.Calendar.Event

  @static ~w(/ /aktuell /termine /thron /verein /kontakt /impressum /datenschutz)

  def index(conn, _params) do
    base = Application.get_env(:bbh, :site_url, "https://buterland-beckerhook.de")

    entries =
      Enum.map(@static, &{base <> &1, nil}) ++
        article_entries(base) ++
        event_entries(base)

    body = """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    #{Enum.map_join(entries, "\n", &url_element/1)}
    </urlset>
    """

    conn |> put_resp_content_type("application/xml") |> send_resp(200, body)
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

  defp url_element({loc, nil}), do: "  <url><loc>#{loc}</loc></url>"

  defp url_element({loc, %DateTime{} = dt}) do
    "  <url><loc>#{loc}</loc><lastmod>#{DateTime.to_date(dt)}</lastmod></url>"
  end
end
