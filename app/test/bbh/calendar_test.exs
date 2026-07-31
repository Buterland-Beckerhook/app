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

    test "keeps an in-progress event over a later upcoming one" do
      ongoing = event_fixture(starts_at: at(-1), ends_at: at(1))
      _upcoming = event_fixture(starts_at: at(3))

      assert Calendar.next_event().id == ongoing.id
    end

    test "drops an event once it has ended" do
      _ended = event_fixture(starts_at: at(-2), ends_at: at(-1))
      upcoming = event_fixture(starts_at: at(3))

      assert Calendar.next_event().id == upcoming.id
    end

    test "keeps an all-day event through the end of its day" do
      today = Bbh.Time.now() |> DateTime.to_date()
      midnight = DateTime.new!(today, ~T[00:00:00], "Etc/UTC")
      today_event = event_fixture(starts_at: midnight, all_day: true)
      _upcoming = event_fixture(starts_at: at(3))

      assert Calendar.next_event().id == today_event.id
    end
  end

  describe "end time" do
    test "a timed event without an end keeps a nil end" do
      {:ok, event} =
        Calendar.create_event(%{
          status: "published",
          title: "Fest",
          slug: "fest-#{System.unique_integer([:positive])}",
          starts_at: ~U[2027-06-01 10:00:00Z]
        })

      assert is_nil(event.ends_at)
    end

    test "an all-day event keeps a nil end (and its start time)" do
      {:ok, event} =
        Calendar.create_event(%{
          status: "published",
          title: "Ganztag",
          slug: "ganztag-#{System.unique_integer([:positive])}",
          starts_at: ~U[2027-06-01 10:00:00Z],
          all_day: true
        })

      assert event.all_day
      assert is_nil(event.ends_at)
      assert event.starts_at == ~U[2027-06-01 10:00:00Z]
    end

    test "an explicit end is left untouched" do
      {:ok, event} =
        Calendar.create_event(%{
          status: "published",
          title: "Mit Ende",
          slug: "ende-#{System.unique_integer([:positive])}",
          starts_at: ~U[2027-06-01 10:00:00Z],
          ends_at: ~U[2027-06-01 14:00:00Z]
        })

      assert event.ends_at == ~U[2027-06-01 14:00:00Z]
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

  describe "internal calendar events drop public-only fields" do
    @reminder_params %{
      "reminders_sort" => ["0"],
      "reminders" => %{"0" => %{"lead_days" => "7", "text" => "bald"}}
    }

    defp base_attrs(extra) do
      Map.merge(
        %{
          "status" => "published",
          "title" => "T",
          "slug" => "t-#{System.unique_integer([:positive])}",
          "starts_at" => ~U[2027-06-01 10:00:00Z],
          "announce" => true,
          "show_countdown" => true
        },
        extra
      )
    end

    defp reminders(event), do: Bbh.Repo.all(Ecto.assoc(event, :reminders))

    test "create_event forces announce/countdown off and drops reminders for an internal calendar" do
      {:ok, event} =
        Calendar.create_event(
          base_attrs(Map.merge(%{"calendar" => "vorstand"}, @reminder_params))
        )

      refute event.announce
      refute event.show_countdown
      assert reminders(event) == []
    end

    test "public events keep announce, countdown and reminders" do
      {:ok, event} = Calendar.create_event(base_attrs(@reminder_params))

      assert event.announce
      assert event.show_countdown
      assert [%{lead_days: 7}] = reminders(event)
    end

    test "switching an existing public event to an internal calendar clears its reminders" do
      {:ok, event} = Calendar.create_event(base_attrs(@reminder_params))
      assert [_] = reminders(event)

      {:ok, updated} = Calendar.update_event(event, %{"calendar" => "offiziere"})

      refute updated.announce
      refute updated.show_countdown
      assert reminders(updated) == []
    end
  end
end
