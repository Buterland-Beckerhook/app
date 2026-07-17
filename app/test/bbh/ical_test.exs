defmodule Bbh.ICalTest do
  use Bbh.DataCase, async: true

  alias Bbh.{Calendar, ICal}

  import Bbh.CalendarFixtures

  setup do
    location = location_fixture(name: "Halle", street: "Weg 1", zip: "48429", city: "Rheine")

    event =
      event_fixture(
        title: "Fest, mit Komma",
        slug: "fest",
        starts_at: ~U[2027-06-01 18:00:00Z],
        ends_at: ~U[2027-06-01 22:00:00Z],
        body: "<p>Ein Text</p>",
        location_id: location.id
      )
      |> Map.get(:id)
      |> Calendar.get_event!()

    %{event: event}
  end

  describe "feed/2" do
    test "emits a valid VCALENDAR with the event", %{event: event} do
      ics = ICal.feed([event], "https://example.de")

      assert ics =~ "BEGIN:VCALENDAR"
      assert ics =~ "VERSION:2.0"
      assert ics =~ "BEGIN:VEVENT"
      assert ics =~ "END:VEVENT"
      assert ics =~ "END:VCALENDAR"

      # Times are emitted in Europe/Berlin (with a VTIMEZONE), not UTC.
      assert ics =~ "BEGIN:VTIMEZONE"
      assert ics =~ "TZID:Europe/Berlin"
      assert ics =~ "DTSTART;TZID=Europe/Berlin:20270601T180000"
      assert ics =~ "DTEND;TZID=Europe/Berlin:20270601T220000"
      refute ics =~ "DTSTART:20270601T180000Z"
      assert ics =~ "URL:https://example.de/termine/2027/fest"
      # comma is escaped per RFC 5545
      assert ics =~ "SUMMARY:Fest\\, mit Komma"
      # location is joined and escaped
      assert ics =~ "LOCATION:Halle\\, Weg 1\\, 48429 Rheine"
      # html is stripped from the description
      assert ics =~ "DESCRIPTION:Ein Text"
    end

    test "uses the configured time zone as the TZID", %{event: event} do
      previous = Application.get_env(:bbh, :time_zone)
      Application.put_env(:bbh, :time_zone, "Europe/Amsterdam")
      on_exit(fn -> Application.put_env(:bbh, :time_zone, previous) end)

      ics = ICal.feed([event], "https://example.de")

      assert ics =~ "TZID:Europe/Amsterdam"
      assert ics =~ "DTSTART;TZID=Europe/Amsterdam:20270601T180000"
      assert ics =~ "DTEND;TZID=Europe/Amsterdam:20270601T220000"
      refute ics =~ "Europe/Berlin"
    end
  end

  describe "single/2" do
    test "wraps one event in a feed", %{event: event} do
      assert ICal.single(event, "https://example.de") == ICal.feed([event], "https://example.de")
    end
  end
end
