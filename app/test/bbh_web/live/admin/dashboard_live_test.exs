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
end
