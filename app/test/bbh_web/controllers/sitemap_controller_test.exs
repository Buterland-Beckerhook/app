defmodule BbhWeb.SitemapControllerTest do
  use BbhWeb.ConnCase, async: true

  import Bbh.ContentFixtures
  import Bbh.CalendarFixtures

  test "GET /sitemap.xml returns XML with static, article and event URLs", %{conn: conn} do
    article = article_fixture()
    event = event_fixture()

    conn = get(conn, ~p"/sitemap.xml")

    assert response_content_type(conn, :xml) =~ "application/xml"
    body = response(conn, 200)

    assert body =~ "<urlset"
    assert body =~ "/aktuell</loc>"
    assert body =~ "/aktuell/#{article.year}/#{article.slug}"
    assert body =~ "/termine/#{event.year}/#{event.slug}"
  end

  test "lists indexable pages by placement and leaves out noindex/system pages", %{conn: conn} do
    page_fixture(slug: "chronik", placement: "menu")
    page_fixture(slug: "anfahrt", placement: "unlisted")
    page_fixture(slug: "geheim-x7k2", placement: "unlisted", noindex: true)
    page_fixture(slug: "intern", placement: "menu", noindex: true)
    page_fixture(slug: "impressum", placement: "system")
    page_fixture(slug: "baustein", placement: "system")

    body = conn |> get(~p"/sitemap.xml") |> response(200)

    assert body =~ "/verein/chronik</loc>"
    assert body =~ "/seite/anfahrt</loc>"
    assert body =~ "/impressum</loc>"
    refute body =~ "geheim-x7k2"
    refute body =~ "/verein/intern"
    refute body =~ "baustein"
  end
end
