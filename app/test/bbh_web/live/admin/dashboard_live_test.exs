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

  test "shows the Postfach widget to an admin with a strong session", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin")
    render_async(lv, 2000)

    assert has_element?(lv, "#tickets-widget")
  end

  test "shows top articles and search terms to an admin", %{conn: conn} do
    article = article_fixture(title: "Königsschießen")
    Bbh.Analytics.record(%{path: "/aktuell/#{article.year}/#{article.slug}"})
    Bbh.Analytics.record_search(%{term: "Vogelschießen", hits: 0})

    {:ok, lv, _html} = live(conn, ~p"/admin")
    render_async(lv, 2000)

    assert lv |> element("#top-articles") |> render() =~ "Königsschießen"
    html = lv |> element("#top-searches") |> render()
    assert html =~ "vogelschießen"
    assert html =~ "ohne Treffer"
  end

  describe "as an editor with a strong session" do
    setup do
      %{conn: log_in_user(build_conn(), Bbh.AccountsFixtures.user_fixture())}
    end

    test "shows the basic access figures, not the admin-only ones", %{conn: conn} do
      article = article_fixture(title: "Königsschießen")
      path = "/aktuell/#{article.year}/#{article.slug}"
      Bbh.Analytics.record(%{path: path, referrer_host: "google.com"})
      Bbh.Analytics.record_search(%{term: "Vogelschießen", hits: 0})

      {:ok, lv, _html} = live(conn, ~p"/admin")
      html = render_async(lv, 2000)

      assert html =~ "Zugriffe"
      assert html =~ "Seitenaufrufe"
      assert html =~ "Besuche"
      assert html =~ "Top-Seiten"
      assert lv |> element("#top-articles") |> render() =~ "Königsschießen"

      refute html =~ "Top-Verweise"
      refute html =~ "google.com"
      refute has_element?(lv, "#top-searches")
      refute html =~ "iCal-Abrufe"
      refute html =~ "Push-Abos"
      refute has_element?(lv, "#ical-clients")

      # The range selector works for them too.
      assert lv |> element("button", "7 Tage") |> render_click() =~ "Zugriffe"
      render_async(lv, 2000)
    end
  end

  describe "without any access" do
    setup do
      {:ok, user} = Bbh.AccountsFixtures.user_fixture() |> Bbh.Accounts.update_user_role("none")
      %{conn: log_in_user(build_conn(), user), none_user: user}
    end

    test "shows only the notice, no widgets and no Übersicht menu entry", %{conn: conn} do
      article_fixture()
      Bbh.Analytics.record(%{path: "/aktuell"})

      {:ok, lv, _html} = live(conn, ~p"/admin")
      html = render_async(lv, 2000)

      assert has_element?(lv, "#no-access")
      assert html =~ "keine Berechtigungen"
      assert has_element?(lv, ~s|#no-access a[href="/kontakt"]|)

      refute has_element?(lv, ~s|a[data-phx-link][href="/admin"]|, "Übersicht")
      refute html =~ "Zugriffe"
      refute html =~ ~s(href="/admin/artikel")
      refute html =~ ~s(href="/admin/termine")
    end

    test "shows the scheduled deletion date", %{conn: conn, none_user: user} do
      date = Date.add(Bbh.Accounts.local_today(), 10)
      {:ok, _} = Bbh.Accounts.schedule_user_deletion(user, date)

      {:ok, lv, _html} = live(conn, ~p"/admin")
      render_async(lv, 2000)

      assert lv |> element("#delete-on-notice") |> render() =~ BbhWeb.Format.de_date(date)
    end
  end

  describe "with a plain magic-link session" do
    # The dashboard itself stays open (Termine editors land here), but ticket subjects
    # and visitor analytics belong to the strong-auth areas.
    @describetag auth_method: "magic_link"

    test "hides the Postfach widget and the analytics", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin")
      html = render_async(lv, 2000)

      refute has_element?(lv, "#tickets-widget")
      refute html =~ "Zugriffe"

      # A forced range change loads nothing either.
      render_click(lv, "set_range", %{"days" => "7"})
      refute render(lv) =~ "Zugriffe"
    end
  end
end
