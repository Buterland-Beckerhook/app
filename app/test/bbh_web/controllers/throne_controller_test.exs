defmodule BbhWeb.ThroneControllerTest do
  use BbhWeb.ConnCase, async: true

  import Bbh.ContentFixtures

  test "GET /thron lists thrones", %{conn: conn} do
    throne_fixture(king: "Friedrich der Erste", queen: "Wilhelmine die Erste")
    html = conn |> get(~p"/thron") |> html_response(200)

    assert html =~ "Throne" or html =~ "Thron"
    assert html =~ "Friedrich der Erste"
    # A normal (König) throne still shows the queen row.
    assert html =~ "Königin"
    assert html =~ "Wilhelmine die Erste"
  end

  test "GET /thron renders with no thrones", %{conn: conn} do
    assert conn |> get(~p"/thron") |> html_response(200)
  end

  test "GET /thron shows title + regency name + years in the heading", %{conn: conn} do
    throne_fixture(
      type: "koenig",
      king_title: "Jan-Bernd I.",
      king: "Jan-Bernd Droste",
      begin_year: 2025,
      end_year: 2026
    )

    html = conn |> get(~p"/thron") |> html_response(200)

    assert html =~ "König Jan-Bernd I."
    assert html =~ "2025–2026"
    # The regency name lives in the heading now, the table shows the real name.
    assert html =~ "Jan-Bernd Droste"
  end

  test "GET /thron renders a Jungschützenkönig as king-only when no queen is set", %{conn: conn} do
    throne_fixture(type: "jungschuetzenkoenig", king: "Tim Junior", queen: nil)

    html = conn |> get(~p"/thron/jungschuetzenkoenig") |> html_response(200)

    assert html =~ "Jungschützenkönig"
    assert html =~ "Tim Junior"
    # No queen and no court rows when there's no data for them.
    refute html =~ "önigin"
    refute html =~ "Ehrenpaare"
  end

  test "GET /thron shows a Jungschützenkönig's queen and court when present", %{conn: conn} do
    throne_fixture(
      type: "jungschuetzenkoenig",
      king: "Alt-König",
      queen: "Alt-Königin",
      moh1: "Ehrendame Eins",
      cupbearer: "Mundschenk Max"
    )

    html = conn |> get(~p"/thron/jungschuetzenkoenig") |> html_response(200)

    # Queen and court are optional but shown when entered (historical entries).
    assert html =~ "Königin"
    assert html =~ "Alt-Königin"
    assert html =~ "Ehrendame Eins"
    assert html =~ "Mundschenk Max"
  end

  test "GET /thron renders the year-king pager", %{conn: conn} do
    throne_fixture(begin_year: 2018, end_year: 2019, king: "Gerd Lübbers")
    throne_fixture(begin_year: 2023, end_year: 2024, king: "Jan-Bernd Droste")

    html = conn |> get(~p"/thron") |> html_response(200)

    assert html =~ "data-nav-select"
    # Newest throne is shown first; the older one is reachable via the next link,
    # addressed by its year rather than its (shifting) position.
    assert html =~ "2023–2024 – Jan-Bernd Droste"
    assert html =~ "/thron?jahr=2018"
    refute html =~ "seite="
  end

  describe "stable year URLs" do
    setup do
      throne_fixture(begin_year: 1995, end_year: 1996, king: "Ludger Bußjan")
      throne_fixture(begin_year: 2018, end_year: 2019, king: "Gerd Lübbers")
      throne_fixture(begin_year: 2023, end_year: 2024, king: "Jan-Bernd Droste")
      :ok
    end

    test "?jahr= shows the throne of that year with a year-specific title", %{conn: conn} do
      html = conn |> get(~p"/thron?jahr=1995") |> html_response(200)

      assert html =~ "Ludger Bußjan"
      assert html =~ ~s(<meta property="og:title" content="Throne 1995–1996">)
      # Neighbours and the select point at year URLs; the shown throne is selected.
      assert html =~ ~s(href="/thron?jahr=2018")
      assert html =~ ~s(value="/thron?jahr=1995" selected)
    end

    test "the bare list URL shows the newest throne under the section title", %{conn: conn} do
      html = conn |> get(~p"/thron") |> html_response(200)

      assert html =~ "Jan-Bernd Droste"
      assert html =~ ~s(<meta property="og:title" content="Throne">)
    end

    test "legacy ?seite=N permanently redirects to the throne now at that position",
         %{conn: conn} do
      conn = get(conn, ~p"/thron?seite=3")
      assert conn.status == 301
      assert redirected_to(conn, 301) == "/thron?jahr=1995"
    end

    test "?seite= past the end redirects to the list", %{conn: conn} do
      assert conn |> get(~p"/thron?seite=99") |> redirected_to(301) == "/thron"
    end

    test "an unknown or malformed year is a 404", %{conn: conn} do
      assert conn |> get(~p"/thron?jahr=1990") |> response(404)
      assert conn |> get(~p"/thron?jahr=abc") |> response(404)
    end

    test "?jahr= is scoped to the list's throne type", %{conn: conn} do
      throne_fixture(type: "stadtkaiser", begin_year: 2000, end_year: nil, king: "Ludger")

      assert conn |> get(~p"/thron/stadtkaiser?jahr=2000") |> html_response(200) =~ "Ludger"

      # 1995 is a König, not a Stadtkaiser.
      assert conn |> get(~p"/thron/stadtkaiser?jahr=1995") |> response(404)

      assert conn |> get(~p"/thron/stadtkaiser?seite=1") |> redirected_to(301) ==
               "/thron/stadtkaiser?jahr=2000"
    end
  end

  test "GET /thron only lists Könige, not other throne types", %{conn: conn} do
    throne_fixture(type: "koenig", king: "König Karl")
    throne_fixture(type: "stadtkaiser", king: "Stadtkaiser Sven")
    throne_fixture(type: "jungschuetzenkoenig", king: "Jungkönig Jonas", queen: nil)

    html = conn |> get(~p"/thron") |> html_response(200)

    assert html =~ "König Karl"
    refute html =~ "Stadtkaiser Sven"
    refute html =~ "Jungkönig Jonas"
  end

  test "the Thron menu links published Kaiser articles only", %{conn: conn} do
    published = article_fixture(%{slug: "kaiserthron", title: "Kaiser 1984"})
    draft = article_fixture(%{slug: "kaiserthron-entwurf", title: "Kaiser 1922", status: "draft"})
    throne_fixture(type: "kaiser", begin_year: 1984, king: "Hermann Thebelt", article: published)
    throne_fixture(type: "kaiser", begin_year: 1922, king: "Gerhard Agten", article: draft)

    html = conn |> get(~p"/thron") |> html_response(200)

    assert html =~ "Kaiserthron 1984"
    # A draft has no public page — linking it would be a dead link in the menu.
    refute html =~ "Kaiserthron 1922"
  end

  test "GET /thron/stadtkaiser lists only Stadtkaiser with its own heading", %{conn: conn} do
    throne_fixture(type: "koenig", king: "König Karl")
    throne_fixture(type: "stadtkaiser", king: "Stadtkaiser Sven")

    html = conn |> get(~p"/thron/stadtkaiser") |> html_response(200)

    assert html =~ ">Stadtkaiser</h1>"
    assert html =~ "Stadtkaiser Sven"
    refute html =~ "König Karl"
  end

  test "GET /thron links the throne picture to its article", %{conn: conn} do
    article = article_fixture(slug: "koenigsschiessen", date_published: ~U[2025-07-20 18:00:00Z])

    throne_fixture(
      article: article,
      image_id: upload_fixture().id,
      begin_year: 2025,
      end_year: 2026
    )

    html = conn |> get(~p"/thron") |> html_response(200)

    # Picture and „Zum Artikel“ both point at the article.
    assert count(html, ~s(href="/aktuell/2025/koenigsschiessen")) == 2
    assert html =~ "Zum Artikel"
  end

  test "GET /thron does not link a „Nur Thron-Anzeige“ entry", %{conn: conn} do
    article = article_fixture(no_article: true, slug: "nur-thron")
    throne_fixture(article: article, image_id: upload_fixture().id)

    html = conn |> get(~p"/thron") |> html_response(200)

    assert html =~ "<img"
    refute html =~ "nur-thron"
    refute html =~ "Zum Artikel"
  end

  test "GET /thron does not link an unpublished article", %{conn: conn} do
    article = article_fixture(status: "draft", slug: "entwurf")
    throne_fixture(article: article, image_id: upload_fixture().id)

    html = conn |> get(~p"/thron") |> html_response(200)

    refute html =~ "entwurf"
    refute html =~ "Zum Artikel"
  end

  defp count(haystack, needle), do: length(String.split(haystack, needle)) - 1

  test "GET /thron with an unknown type returns 404", %{conn: conn} do
    assert conn |> get(~p"/thron/gibtsnicht") |> response(404)
  end
end
