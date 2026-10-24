defmodule BbhWeb.EventControllerTest do
  use BbhWeb.ConnCase, async: true

  import Bbh.CalendarFixtures

  describe "GET /termine" do
    test "renders the events index", %{conn: conn} do
      event = event_fixture(title: "Schützenfest")
      html = conn |> get(~p"/termine?jahr=#{event.year}") |> html_response(200)
      assert html =~ "Termine"
      assert html =~ "Schützenfest"
    end

    test "the subscribe section offers webcal (Apple/Outlook) and a copyable https URL (Google/Android)",
         %{conn: conn} do
      event = event_fixture()
      html = conn |> get(~p"/termine?jahr=#{event.year}") |> html_response(200)

      assert html =~ "Kalender abonnieren"
      # Apple/Outlook: a webcal:// link subscribes (live, re-polled).
      assert html =~ ~r{href="webcal://[^"]*/termine/abo\.ics"}
      # Google/Android: the raw https feed URL as copyable text to paste into
      # Google Calendar (web) — the only path that works there. (Scheme is http in
      # the test env, https in prod; the point is a plain, non-webcal absolute URL.)
      assert html =~ ~r{value="https?://[^"]*/termine/abo\.ics"}
      # Copy-select uses a delegated listener, not inline onclick (CSP blocks the
      # latter in prod — no 'unsafe-inline' in script-src).
      assert html =~ "data-select-on-click"
      refute html =~ "onclick"
      # The one-time .ics download link is still offered.
      assert html =~ ~s{href="/termine/abo.ics"}
      # The old subscribe link was a bare relative import-once link — guard against
      # regressing to it as the primary action.
      refute html =~ ~s{href="/termine/index.ics"}
    end
  end

  describe "GET /termine/:year/:slug" do
    test "renders a public event", %{conn: conn} do
      event = event_fixture(title: "Königsschießen")
      html = conn |> get(~p"/termine/#{event.year}/#{event.slug}") |> html_response(200)
      assert html =~ "Königsschießen"
    end

    test "the calendar link opens a dialog that leads with the subscription",
         %{conn: conn} do
      event = event_fixture(title: "Königsschießen", enable_ical: true)
      html = conn |> get(~p"/termine/#{event.year}/#{event.slug}") |> html_response(200)
      doc = LazyHTML.from_document(html)
      ics = "/termine/#{event.year}/#{event.slug}/event.ics"

      # Without JavaScript the link still is the event's file.
      [link] = doc |> LazyHTML.query("a[data-calendar-dialog]") |> Enum.to_list()
      assert LazyHTML.attribute(link, "href") == [ics]
      assert LazyHTML.text(link) =~ "Zum Kalender hinzufügen"
      refute html =~ "(.ics)"

      [dialog_id] = LazyHTML.attribute(link, "data-calendar-dialog")
      dialog = LazyHTML.query(doc, "dialog##{dialog_id}")

      assert LazyHTML.text(dialog) =~
               "Alle Termine automatisch im eigenen Kalender, immer aktuell."

      assert dialog |> LazyHTML.query(~s(a[href^="webcal://"])) |> Enum.count() == 1
      assert dialog |> LazyHTML.query(~s(a[href="#{ics}"])) |> LazyHTML.text() =~ "Königsschießen"
    end

    test "links the location to OpenStreetMap, never Google", %{conn: conn} do
      location = location_fixture(lat: 52.2063619, lng: 7.0017587)
      event = event_fixture(location_id: location.id)
      html = conn |> get(~p"/termine/#{event.year}/#{event.slug}") |> html_response(200)

      assert html =~ "https://www.openstreetmap.org/?mlat=52.206362&amp;mlon=7.001759"
      assert html =~ "https://www.openstreetmap.org/directions?to=52.206362%2C7.001759"
      assert html =~ "Route planen"
      refute html =~ ~r/google\.[a-z.]+\/maps|maps\.google|goo\.gl/
    end

    test "offers no map links for a location without coordinates", %{conn: conn} do
      event = event_fixture(location_id: location_fixture().id)
      html = conn |> get(~p"/termine/#{event.year}/#{event.slug}") |> html_response(200)

      assert html =~ "Schützenhalle"
      refute html =~ "openstreetmap.org"
    end

    test "describes the place with address and coordinates in JSON-LD", %{conn: conn} do
      location = location_fixture(lat: 52.2063619, lng: 7.0017587)
      event = event_fixture(location_id: location.id)
      html = conn |> get(~p"/termine/#{event.year}/#{event.slug}") |> html_response(200)

      [json] =
        html
        |> LazyHTML.from_document()
        |> LazyHTML.query(~s(script[type="application/ld+json"]))
        |> Enum.map(&LazyHTML.text/1)

      place = Jason.decode!(json)["location"]

      assert place["geo"] == %{
               "@type" => "GeoCoordinates",
               "latitude" => 52.2063619,
               "longitude" => 7.0017587
             }

      assert place["address"]["streetAddress"] == "Dorfstraße 1"
      assert place["address"]["postalCode"] == "48429"
    end

    test "returns 404 for an unknown event", %{conn: conn} do
      assert conn |> get(~p"/termine/2026/nada") |> response(404)
    end

    test "hides the admin edit link from anonymous visitors", %{conn: conn} do
      event = event_fixture()
      html = conn |> get(~p"/termine/#{event.year}/#{event.slug}") |> html_response(200)
      refute html =~ "/bearbeiten"
    end
  end

  describe "admin edit affordance" do
    setup :register_and_log_in_admin

    test "shows an edit link to the event form for staff", %{conn: conn} do
      event = event_fixture(title: "Redigierbar")
      html = conn |> get(~p"/termine/#{event.year}/#{event.slug}") |> html_response(200)
      assert html =~ ~p"/admin/termine/#{event.id}/bearbeiten"
    end
  end

  describe "iCal feeds" do
    test "GET /termine/abo.ics returns a calendar", %{conn: conn} do
      event_fixture()
      conn = get(conn, ~p"/termine/abo.ics")

      assert get_resp_header(conn, "content-type") |> hd() =~ "text/calendar"
      assert response(conn, 200) =~ "BEGIN:VCALENDAR"
    end

    test "GET single event .ics", %{conn: conn} do
      event = event_fixture()
      conn = get(conn, ~p"/termine/#{event.year}/#{event.slug}/event.ics")

      assert response(conn, 200) =~ "BEGIN:VEVENT"
    end

    # Apple Calendar validates a webcal subscription with `Accept: text/calendar`;
    # the feed must not be content-negotiated against HTML (it used to 406).
    for path <- ["/termine/abo.ics", "/termine/index.ics"] do
      test "GET #{path} serves Accept: text/calendar clients", %{conn: conn} do
        event_fixture()

        conn =
          conn
          |> put_req_header("accept", "text/calendar")
          |> put_req_header("user-agent", "iOS/18.0 (22A3354) dataaccessd/1.0")
          |> get(unquote(path))

        assert get_resp_header(conn, "content-type") |> hd() =~ "text/calendar"
        assert response(conn, 200) =~ "BEGIN:VCALENDAR"
      end
    end

    test "single event .ics serves Accept: text/calendar clients", %{conn: conn} do
      event = event_fixture()

      conn =
        conn
        |> put_req_header("accept", "text/calendar")
        |> get(~p"/termine/#{event.year}/#{event.slug}/event.ics")

      assert response(conn, 200) =~ "BEGIN:VEVENT"
    end
  end
end
