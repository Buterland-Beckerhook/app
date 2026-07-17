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
    html = render_async(lv)

    assert html =~ "Übersicht"
    assert html =~ "Artikel"
    # The four stat cards link to their sections.
    assert html =~ ~p"/admin/artikel"
    assert html =~ ~p"/admin/termine"
    assert html =~ ~p"/admin/personen"
    assert html =~ ~p"/admin/seiten"
  end

  test "shows the analytics section with recorded page views", %{conn: conn} do
    today = Date.utc_today()
    Bbh.Analytics.record(%{path: "/aktuell", referrer_host: "google.com", day: today})
    Bbh.Analytics.record(%{path: "/aktuell", day: today})

    {:ok, lv, _html} = live(conn, ~p"/admin")
    html = render_async(lv)

    assert html =~ "Zugriffe"
    assert html =~ "Seitenaufrufe"
    assert html =~ "/aktuell"
    assert html =~ "google.com"

    # The range selector re-runs the analytics query.
    assert lv |> element("button", "7 Tage") |> render_click() =~ "Zugriffe"
  end

  test "the account nav links to the settings modal for sign-in methods", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/admin")

    # Passkey and 2FA enrollment live under the settings modal, which the account
    # footer links to.
    assert html =~ ~p"/admin/einstellungen"
  end
end
