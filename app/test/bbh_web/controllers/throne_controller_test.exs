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
    # Newest throne is shown first; the older one is reachable via the next link.
    assert html =~ "2023–2024 – Jan-Bernd Droste"
    assert html =~ "/thron?seite=2"
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

  test "GET /thron/stadtkaiser lists only Stadtkaiser with its own heading", %{conn: conn} do
    throne_fixture(type: "koenig", king: "König Karl")
    throne_fixture(type: "stadtkaiser", king: "Stadtkaiser Sven")

    html = conn |> get(~p"/thron/stadtkaiser") |> html_response(200)

    assert html =~ ">Stadtkaiser</h1>"
    assert html =~ "Stadtkaiser Sven"
    refute html =~ "König Karl"
  end

  test "GET /thron with an unknown type returns 404", %{conn: conn} do
    assert conn |> get(~p"/thron/gibtsnicht") |> response(404)
  end
end
