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

  test "GET /thron renders a Jungschützenkönig as king-only when no queen is set", %{conn: conn} do
    throne_fixture(type: "jungschuetzenkoenig", king: "Tim Junior", queen: nil)

    html = conn |> get(~p"/thron") |> html_response(200)

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

    html = conn |> get(~p"/thron") |> html_response(200)

    # Queen and court are optional but shown when entered (historical entries).
    assert html =~ "Jungschützenkönigin"
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
end
