defmodule BbhWeb.EventProgrammeControllerTest do
  @moduledoc "Public pages of a festival's programme, in both item-page variants."
  # async: false — toggles the global :event_child_pages flag.
  use BbhWeb.ConnCase, async: false

  import Bbh.CalendarFixtures

  setup do
    previous = Application.get_env(:bbh, :event_child_pages, false)
    on_exit(fn -> Application.put_env(:bbh, :event_child_pages, previous) end)

    festzelt = location_fixture(name: "Festzelt")
    dinkelhof = location_fixture(name: "Dinkelhof")

    fest =
      festival_fixture(
        title: "Schützenfest 2030",
        slug: "schuetzenfest",
        location_id: festzelt.id
      )

    item = fn slug, title, starts_at, ends_at, attrs ->
      programme_item_fixture(
        fest,
        Map.merge(%{slug: slug, title: title, starts_at: starts_at, ends_at: ends_at}, attrs)
      )
    end

    tanz = item.("tanz", "Tanz", ~U[2030-07-20 20:00:00Z], ~U[2030-07-21 02:00:00Z], %{})

    gottesdienst =
      item.("gottesdienst", "Gottesdienst", ~U[2030-07-21 09:30:00Z], ~U[2030-07-21 10:30:00Z], %{
        location_id: festzelt.id,
        body: "<p>Im Festzelt, bei jedem Wetter.</p>"
      })

    schnitzel =
      item.(
        "schnitzelessen",
        "Schnitzelessen",
        ~U[2030-07-23 12:00:00Z],
        ~U[2030-07-23 18:00:00Z],
        %{
          status: "canceled",
          cancel_reason: "Fällt aus",
          location_id: dinkelhof.id
        }
      )

    _draft =
      item.("geheim", "Geheimprobe", ~U[2030-07-22 10:00:00Z], ~U[2030-07-22 11:00:00Z], %{
        status: "draft"
      })

    %{fest: fest, tanz: tanz, gottesdienst: gottesdienst, schnitzel: schnitzel}
  end

  defp child_pages(on?), do: Application.put_env(:bbh, :event_child_pages, on?)

  describe "festival page" do
    test "lists the programme by day, without drafts", %{conn: conn} do
      html = conn |> get(~p"/termine/2030/schuetzenfest") |> html_response(200)

      assert html =~ "Festprogramm"
      assert html =~ "Samstag, 20. Juli"
      assert html =~ "Sonntag, 21. Juli"
      assert html =~ "Dienstag, 23. Juli"
      # Overnight item stays on the day it starts.
      assert html =~ "20:00 – 02:00 Uhr"
      assert html =~ ~s(id="gottesdienst")
      assert html =~ "Fällt aus"
      refute html =~ "Geheimprobe"
      # Location only where it differs from the festival's.
      assert html =~ "Dinkelhof"
      # Item text, collapsed.
      assert html =~ "Mehr erfahren"
      assert html =~ "Im Festzelt, bei jedem Wetter."
      assert html =~ ~s("subEvent")
      assert html =~ "Fest und Programm zum Kalender hinzufügen"
    end

    test "/termine shows the festival with its item count, never the items", %{conn: conn} do
      html = conn |> get(~p"/termine?jahr=2030") |> html_response(200)

      assert html =~ "Schützenfest 2030"
      assert html =~ "3 Programmpunkte"
      refute html =~ "Gottesdienst"
    end
  end

  describe "items as anchors (default)" do
    setup do: child_pages(false)

    test "an item URL redirects permanently to its anchor", %{conn: conn} do
      conn = get(conn, ~p"/termine/2030/schuetzenfest/gottesdienst")
      assert redirected_to(conn, 301) == "/termine/2030/schuetzenfest#gottesdienst"
    end

    test "unknown, draft and download URLs are not found", %{conn: conn} do
      assert conn |> get(~p"/termine/2030/schuetzenfest/gibtsnicht") |> html_response(404)
      assert build_conn() |> get(~p"/termine/2030/schuetzenfest/geheim") |> html_response(404)

      assert build_conn()
             |> get(~p"/termine/2030/schuetzenfest/gottesdienst/event.ics")
             |> response(404)
    end

    test "the festival page does not link the items", %{conn: conn} do
      html = conn |> get(~p"/termine/2030/schuetzenfest") |> html_response(200)
      refute html =~ ~s(href="/termine/2030/schuetzenfest/gottesdienst")
    end
  end

  describe "items as pages" do
    setup do: child_pages(true)

    test "an item has its own page with the festival and its neighbours", %{conn: conn} do
      html = conn |> get(~p"/termine/2030/schuetzenfest/gottesdienst") |> html_response(200)

      assert html =~ "Gottesdienst"
      assert html =~ "Teil von:"
      assert html =~ ~s(href="/termine/2030/schuetzenfest#programm")
      assert html =~ "Im Festzelt, bei jedem Wetter."
      # previous / next, skipping the draft
      assert html =~ ~s(href="/termine/2030/schuetzenfest/tanz")
      assert html =~ ~s(href="/termine/2030/schuetzenfest/schnitzelessen")
      refute html =~ "Geheimprobe"
    end

    test "the festival page links the items", %{conn: conn} do
      html = conn |> get(~p"/termine/2030/schuetzenfest") |> html_response(200)
      assert html =~ ~s(href="/termine/2030/schuetzenfest/gottesdienst")
    end

    test "an item has its own download", %{conn: conn} do
      ics = conn |> get(~p"/termine/2030/schuetzenfest/gottesdienst/event.ics") |> response(200)

      assert ics =~ "SUMMARY:Gottesdienst"
      assert ics =~ "/termine/2030/schuetzenfest/gottesdienst"
      refute ics =~ "SUMMARY:Schützenfest"
    end

    test "unknown and draft items are not found", %{conn: conn} do
      assert conn |> get(~p"/termine/2030/schuetzenfest/geheim") |> html_response(404)
      assert build_conn() |> get(~p"/termine/2030/anderes/gottesdienst") |> html_response(404)
    end
  end

  describe "iCal" do
    test "the festival download carries every visible item as its own event", %{
      conn: conn,
      fest: fest
    } do
      ics = conn |> get(~p"/termine/2030/schuetzenfest/event.ics") |> response(200)

      assert length(String.split(ics, "BEGIN:VEVENT")) - 1 == 4
      assert ics =~ "DTSTART;VALUE=DATE:20300720"
      assert ics =~ "DTEND;VALUE=DATE:20300724"
      assert ics =~ "SUMMARY:Gottesdienst"
      assert ics =~ "DTSTART;TZID=Europe/Berlin:20300721T093000"
      assert ics =~ "RELATED-TO;RELTYPE=PARENT:#{fest.id}@buterland-beckerhook.de"
      assert ics =~ "URL:https://buterland-beckerhook.de/termine/2030/schuetzenfest#gottesdienst"
      assert ics =~ "STATUS:CANCELLED"
      refute ics =~ "Geheimprobe"
    end

    test "the subscription feed carries the items too", %{conn: conn} do
      ics = conn |> get(~p"/termine/abo.ics") |> response(200)

      assert ics =~ "SUMMARY:Schützenfest 2030"
      assert ics =~ "SUMMARY:Gottesdienst"
      refute ics =~ "Geheimprobe"
    end
  end
end
