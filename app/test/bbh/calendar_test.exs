defmodule Bbh.CalendarTest do
  use Bbh.DataCase, async: true

  alias Bbh.Calendar

  import Bbh.CalendarFixtures

  defp at(offset_days) do
    DateTime.utc_now() |> DateTime.add(offset_days, :day) |> DateTime.truncate(:second)
  end

  describe "next_event/1" do
    test "returns the soonest upcoming public event" do
      _past = event_fixture(starts_at: at(-2))
      soon = event_fixture(starts_at: at(1))
      _later = event_fixture(starts_at: at(5))

      assert Calendar.next_event().id == soon.id
    end

    test "ignores non-public events (draft, not announced, or internal calendar)" do
      event_fixture(starts_at: at(1), status: "draft")
      event_fixture(starts_at: at(1), announce: false)
      event_fixture(starts_at: at(1), calendar: "vorstand")

      refute Calendar.next_event()
    end
  end

  describe "list_events_by_year/1 and event_years/0" do
    test "lists a year's public events chronologically" do
      first = event_fixture(starts_at: ~U[2027-03-01 10:00:00Z])
      second = event_fixture(starts_at: ~U[2027-09-01 10:00:00Z])
      _other_year = event_fixture(starts_at: ~U[2028-01-01 10:00:00Z])

      events = Calendar.list_events_by_year(2027)
      assert Enum.map(events, & &1.id) == [first.id, second.id]
    end

    test "event_years lists distinct years, newest first" do
      event_fixture(starts_at: ~U[2027-03-01 10:00:00Z])
      event_fixture(starts_at: ~U[2027-09-01 10:00:00Z])
      event_fixture(starts_at: ~U[2028-01-01 10:00:00Z])

      assert Calendar.event_years() == [2028, 2027]
    end
  end

  describe "get_public_event/2" do
    test "returns a public event by slug and year with its location" do
      location = location_fixture()

      event =
        event_fixture(
          slug: "schuetzenfest",
          starts_at: ~U[2027-06-01 10:00:00Z],
          location_id: location.id
        )

      found = Calendar.get_public_event("schuetzenfest", 2027)
      assert found.id == event.id
      assert found.location.id == location.id
    end

    test "does not return a draft event" do
      event_fixture(slug: "intern", status: "draft", starts_at: ~U[2027-06-01 10:00:00Z])
      refute Calendar.get_public_event("intern", 2027)
    end
  end

  describe "list_events_for/1" do
    alias Bbh.Accounts.User

    setup do
      public = event_fixture(slug: "oeffentlich", calendar: nil)
      vorstand = event_fixture(slug: "vorstand-sitzung", calendar: "vorstand")
      offiziere = event_fixture(slug: "offiziere-treffen", calendar: "offiziere")
      %{public: public, vorstand: vorstand, offiziere: offiziere}
    end

    defp ids(events), do: events |> Enum.map(& &1.id) |> Enum.sort()

    test "admin sees every event", ctx do
      admin = %User{role: "admin", calendars: []}

      assert ids(Calendar.list_events_for(admin)) ==
               ids([ctx.public, ctx.vorstand, ctx.offiziere])
    end

    test "editor sees public plus granted calendars", ctx do
      editor = %User{role: "editor", calendars: ["vorstand"]}
      assert ids(Calendar.list_events_for(editor)) == ids([ctx.public, ctx.vorstand])
    end

    test "calendar editor sees only granted calendars", ctx do
      cal = %User{role: "calendar_editor", calendars: ["vorstand"]}
      assert ids(Calendar.list_events_for(cal)) == ids([ctx.vorstand])
    end
  end

  describe "location_options/0" do
    test "returns {name, id} tuples sorted by name" do
      b = location_fixture(name: "Bürgerhaus")
      a = location_fixture(name: "Altes Rathaus")

      assert Calendar.location_options() == [{"Altes Rathaus", a.id}, {"Bürgerhaus", b.id}]
    end
  end
end
