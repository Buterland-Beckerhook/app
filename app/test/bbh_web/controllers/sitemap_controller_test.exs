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
end
