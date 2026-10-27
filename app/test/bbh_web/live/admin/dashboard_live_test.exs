defmodule BbhWeb.Admin.DashboardLiveTest do
  use BbhWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Bbh.ContentFixtures
  import Bbh.CalendarFixtures
  import Bbh.ClubFixtures

  setup :register_and_log_in_admin

  test "renders the dashboard and loads counts asynchronously", %{conn: conn} do
    article_fixture()
    article_fixture()
    event_fixture()
    person_fixture()
    page_fixture()

    {:ok, lv, _html} = live(conn, ~p"/admin")
    # Generous timeout: the DB-backed async assigns can exceed the 100 ms default
    # under parallel test load, which flaked CI.
    html = render_async(lv, 2000)

    assert html =~ "Übersicht"
    assert html =~ "Artikel"
    # The four stat cards link to their sections.
    assert html =~ ~p"/admin/artikel"
    assert html =~ ~p"/admin/termine"
    assert html =~ ~p"/admin/personen"
    assert html =~ ~p"/admin/seiten"
  end

  test "breaks the article and event counts down by status", %{conn: conn} do
    article_fixture(%{status: "published"})
    article_fixture(%{status: "draft"})
    article_fixture(%{status: "draft"})
    event_fixture(%{status: "canceled"})

    {:ok, lv, _html} = live(conn, ~p"/admin")
    html = render_async(lv, 2000)

    assert html =~ ~r/>1<\/span> veröffentlicht/
    assert html =~ ~r/>2<\/span> Entwürfe/
    assert html =~ ~r/>1<\/span> abgesagt/

    # Each count opens its list filtered to that status.
    assert html =~ ~s(href="/admin/artikel?status=draft")
    assert html =~ ~s(href="/admin/termine?status=canceled")
  end

  test "shows the analytics section with recorded page views", %{conn: conn} do
    today = Date.utc_today()
    Bbh.Analytics.record(%{path: "/aktuell", referrer_host: "google.com", day: today})
    Bbh.Analytics.record(%{path: "/aktuell", day: today})

    {:ok, lv, _html} = live(conn, ~p"/admin")
    # Generous timeout: the DB-backed async assigns can exceed the 100 ms default
    # under parallel test load, which flaked CI.
    html = render_async(lv, 2000)

    assert html =~ "Zugriffe"
    assert html =~ "Seitenaufrufe"
    assert html =~ "/aktuell"
    assert html =~ "google.com"

    # The per-day chart shows a scaled axis and a peak caption (two views today).
    assert html =~ "Aufrufe pro Tag"
    assert html =~ "Spitze 2"

    # iCal subscription metrics render alongside the page-view cards.
    assert html =~ "iCal-Abrufe"
    assert html =~ "iCal-Abos"

    # The range selector re-runs the analytics query.
    assert lv |> element("button", "7 Tage") |> render_click() =~ "Zugriffe"
    # Drain that second round of async assigns too, so the LiveView is not killed
    # mid-query at test teardown (which logs a Postgrex disconnect).
    render_async(lv, 2000)
  end

  test "the account nav links to the settings modal for sign-in methods", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/admin")

    # Passkey and 2FA enrollment live under the settings modal, which the account
    # footer links to.
    assert html =~ ~p"/admin/einstellungen"

    # Let the dashboard's async assigns finish before teardown (see above).
    render_async(lv, 2000)
  end

  test "lists iCal subscriptions by calendar app", %{conn: conn} do
    Bbh.Analytics.record_ical(%{visitor_hash: "a", client: "apple"})
    Bbh.Analytics.record_ical(%{visitor_hash: "b", client: "google"})

    {:ok, lv, _html} = live(conn, ~p"/admin")
    html = render_async(lv, 2000)

    assert html =~ "iCal-Abos nach Kalender-App"
    assert html =~ "Apple Kalender"
    assert html =~ "Google Kalender"
  end
end
