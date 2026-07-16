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
  end

  describe "GET /termine/:year/:slug" do
    test "renders a public event", %{conn: conn} do
      event = event_fixture(title: "Königsschießen")
      html = conn |> get(~p"/termine/#{event.year}/#{event.slug}") |> html_response(200)
      assert html =~ "Königsschießen"
    end

    test "returns 404 for an unknown event", %{conn: conn} do
      assert conn |> get(~p"/termine/2026/nada") |> response(404)
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
  end
end
