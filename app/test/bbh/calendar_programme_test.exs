defmodule Bbh.CalendarProgrammeTest do
  @moduledoc "Festivals and their programme items (parent/child events)."
  use Bbh.DataCase, async: true

  alias Bbh.Calendar
  alias Bbh.Calendar.{Event, EventReminder}

  import Bbh.CalendarFixtures

  defp item_attrs(parent, attrs) do
    Enum.into(attrs, %{
      parent_id: parent.id,
      status: "published",
      title: "Gottesdienst",
      slug: "gottesdienst",
      starts_at: ~U[2030-07-21 09:30:00Z],
      ends_at: ~U[2030-07-21 10:30:00Z]
    })
  end

  defp create_item(parent, attrs \\ %{}), do: Calendar.create_event(item_attrs(parent, attrs))

  describe "programme item changeset" do
    test "a timed item within the festival is valid, inheriting what it must" do
      parent = festival_fixture(calendar: "vorstand")

      assert {:ok, item} = create_item(parent, show_countdown: true, calendar: nil)

      assert item.parent_id == parent.id
      assert item.calendar == "vorstand"
      refute item.show_countdown
      # Pre-marked, so the "Neuer Termin" push can never pick it up.
      assert item.notified_at
    end

    test "the parent must exist, be top-level and be an all-day festival over several days" do
      assert %{parent_id: ["existiert nicht"]} =
               errors_on(Event.changeset(%Event{}, item_attrs(%{id: Ecto.UUID.generate()}, %{})))

      fest = festival_fixture()
      item = programme_item_fixture(fest)
      assert {:error, cs} = create_item(item)
      assert %{parent_id: ["ist selbst ein Programmpunkt"]} = errors_on(cs)

      timed =
        event_fixture(starts_at: ~U[2030-07-20 10:00:00Z], ends_at: ~U[2030-07-22 10:00:00Z])

      assert {:error, cs} = create_item(timed)
      assert %{parent_id: ["muss ganztägig sein und mehrere Tage umfassen"]} = errors_on(cs)

      one_day = festival_fixture(ends_at: ~U[2030-07-20 00:00:00Z])
      assert {:error, cs} = create_item(one_day)
      assert %{parent_id: [_]} = errors_on(cs)
    end

    test "an event cannot be its own parent" do
      fest = festival_fixture()

      assert {:error, cs} = Calendar.update_event(fest, %{parent_id: fest.id})
      assert %{parent_id: ["kann nicht der Termin selbst sein"]} = errors_on(cs)
    end

    test "an item has times: not all-day, and with an end" do
      fest = festival_fixture()

      assert {:error, cs} = create_item(fest, all_day: true)
      assert %{all_day: [_]} = errors_on(cs)

      assert {:error, cs} = create_item(fest, ends_at: nil)
      assert %{ends_at: ["muss für Programmpunkte gesetzt sein"]} = errors_on(cs)
    end

    test "an item lies within the festival, with an overnight grace until 06:00" do
      fest = festival_fixture()

      assert {:ok, _} = create_item(fest, slug: "auftakt", starts_at: ~U[2030-07-20 00:00:00Z])

      assert {:error, cs} = create_item(fest, starts_at: ~U[2030-07-19 23:59:00Z])
      assert %{starts_at: ["liegt vor dem ersten Festtag"]} = errors_on(cs)

      assert {:ok, _} =
               create_item(fest,
                 slug: "kehraus",
                 starts_at: ~U[2030-07-23 20:00:00Z],
                 ends_at: ~U[2030-07-24 06:00:00Z]
               )

      assert {:error, cs} =
               create_item(fest,
                 slug: "zu-lang",
                 starts_at: ~U[2030-07-23 20:00:00Z],
                 ends_at: ~U[2030-07-24 06:01:00Z]
               )

      assert %{ends_at: [_]} = errors_on(cs)
    end

    test "no grandchildren: an event with items cannot become an item itself" do
      fest = festival_fixture()
      _item = programme_item_fixture(fest)
      other = festival_fixture()

      assert {:error, cs} = Calendar.update_event(fest, %{parent_id: other.id})
      assert %{parent_id: ["geht nicht: der Termin hat selbst Programmpunkte"]} = errors_on(cs)
    end

    test "a festival with items keeps containing them" do
      fest = festival_fixture()

      _early =
        programme_item_fixture(fest,
          title: "Kinderfest",
          starts_at: ~U[2030-07-20 14:00:00Z],
          ends_at: ~U[2030-07-20 18:00:00Z]
        )

      _late =
        programme_item_fixture(fest,
          title: "Kehraus",
          starts_at: ~U[2030-07-23 20:00:00Z],
          ends_at: ~U[2030-07-24 02:00:00Z]
        )

      assert {:error, cs} = Calendar.update_event(fest, %{ends_at: ~U[2030-07-22 00:00:00Z]})
      assert %{ends_at: ["„Kehraus“ läge dann außerhalb des Festes"]} = errors_on(cs)

      assert {:error, cs} = Calendar.update_event(fest, %{starts_at: ~U[2030-07-21 00:00:00Z]})
      assert %{ends_at: ["„Kinderfest“ läge dann außerhalb des Festes"]} = errors_on(cs)

      assert {:error, cs} = Calendar.update_event(fest, %{all_day: false})
      assert %{all_day: [_]} = errors_on(cs)

      assert {:ok, _} = Calendar.update_event(fest, %{ends_at: ~U[2030-07-24 00:00:00Z]})
      assert {:ok, _} = Calendar.update_event(fest, %{title: "Großes Schützenfest"})
    end

    test "slugs are unique per festival, not against top-level events or other festivals" do
      fest_2030 = festival_fixture()

      fest_2031 =
        festival_fixture(starts_at: ~U[2031-07-19 00:00:00Z], ends_at: ~U[2031-07-22 00:00:00Z])

      assert {:ok, _} = create_item(fest_2030)

      assert {:ok, _} =
               create_item(fest_2031,
                 starts_at: ~U[2031-07-20 09:30:00Z],
                 ends_at: ~U[2031-07-20 10:30:00Z]
               )

      # A standalone "Gottesdienst" the same year does not collide with the item.
      assert %Event{} = event_fixture(slug: "gottesdienst", starts_at: ~U[2030-12-24 16:00:00Z])

      assert {:error, cs} = create_item(fest_2030, title: "Noch ein Gottesdienst")
      assert %{slug: ["ist in diesem Programm schon vergeben"]} = errors_on(cs)
    end
  end

  describe "visibility" do
    test "a festival shows its published and canceled items, not its drafts" do
      fest = festival_fixture()
      published = programme_item_fixture(fest, starts_at: ~U[2030-07-21 09:00:00Z])
      canceled = programme_item_fixture(fest, status: "canceled", cancel_reason: "Regen")
      _draft = programme_item_fixture(fest, status: "draft")

      shown = Calendar.get_public_event(fest.slug, 2030)

      assert Enum.map(shown.children, & &1.id) == [published.id, canceled.id]
      assert Enum.all?(shown.children, &(&1.parent.id == fest.id))
    end

    test "items of a draft or internal festival are hidden" do
      draft_fest = festival_fixture(status: "draft")
      internal_fest = festival_fixture(calendar: "vorstand")
      public_fest = festival_fixture()

      for fest <- [draft_fest, internal_fest, public_fest],
          do: programme_item_fixture(fest, slug: "gottesdienst")

      assert Calendar.get_public_child(2030, draft_fest.slug, "gottesdienst") == nil
      assert Calendar.get_public_child(2030, internal_fest.slug, "gottesdienst") == nil

      item = Calendar.get_public_child(2030, public_fest.slug, "gottesdienst")
      assert item.parent.id == public_fest.id

      feed_ids = Enum.map(Calendar.all_public_events(), & &1.id)
      assert item.id in feed_ids
      assert public_fest.id in feed_ids
      refute internal_fest.id in feed_ids
      assert length(feed_ids) == 2
    end

    test "listings, years, the next event and pushes leave items out" do
      fest = festival_fixture()
      _item = programme_item_fixture(fest)
      _draft = programme_item_fixture(fest, status: "draft")

      assert [%Event{id: id, child_count: 1}] = Calendar.list_events_by_year(2030)
      assert id == fest.id
      assert Calendar.event_years() == [2030]
      assert Calendar.next_event(~U[2030-07-21 10:30:00Z]).id == fest.id

      # Even with the item's marker cleared, only the festival is pending.
      Repo.update_all(Event, set: [notified_at: nil])
      assert [%Event{id: ^id}] = Calendar.events_pending_notification(~U[2030-01-01 00:00:00Z])
    end

    test "next_child/2 is the first published item that has not ended" do
      fest = festival_fixture()

      first =
        programme_item_fixture(fest,
          starts_at: ~U[2030-07-21 09:30:00Z],
          ends_at: ~U[2030-07-21 10:30:00Z]
        )

      second =
        programme_item_fixture(fest,
          starts_at: ~U[2030-07-21 10:30:00Z],
          ends_at: ~U[2030-07-21 12:30:00Z]
        )

      _draft =
        programme_item_fixture(fest,
          status: "draft",
          starts_at: ~U[2030-07-21 12:30:00Z],
          ends_at: ~U[2030-07-21 13:00:00Z]
        )

      assert Calendar.next_child(fest, ~U[2030-07-01 00:00:00Z]).id == first.id
      # running
      assert Calendar.next_child(fest, ~U[2030-07-21 10:00:00Z]).id == first.id
      assert Calendar.next_child(fest, ~U[2030-07-21 10:30:00Z]).id == second.id
      assert Calendar.next_child(fest, ~U[2030-07-21 12:30:00Z]) == nil
      assert Calendar.next_child(fest, ~U[2030-07-21 11:00:00Z]).parent.id == fest.id
    end

    test "next_child_to_start/2 skips running and canceled items" do
      fest = festival_fixture()

      running =
        programme_item_fixture(fest,
          starts_at: ~U[2030-07-21 09:30:00Z],
          ends_at: ~U[2030-07-21 10:30:00Z]
        )

      _canceled =
        programme_item_fixture(fest,
          status: "canceled",
          starts_at: ~U[2030-07-21 10:30:00Z],
          ends_at: ~U[2030-07-21 11:00:00Z]
        )

      later =
        programme_item_fixture(fest,
          starts_at: ~U[2030-07-21 14:00:00Z],
          ends_at: ~U[2030-07-21 15:00:00Z]
        )

      now = ~U[2030-07-21 10:00:00Z]
      assert Calendar.next_child(fest, now).id == running.id
      assert Calendar.next_child_to_start(fest, now).id == later.id
      # The canceled item is never highlighted, even during its slot.
      assert Calendar.next_child(fest, ~U[2030-07-21 10:45:00Z]).id == later.id
      assert Calendar.next_child_to_start(fest, ~U[2030-07-21 14:00:00Z]) == nil
    end

    test "next_event/1 keeps a festival until its last item has ended" do
      fest = festival_fixture()

      _kehraus =
        programme_item_fixture(fest,
          starts_at: ~U[2030-07-23 20:00:00Z],
          ends_at: ~U[2030-07-24 02:00:00Z]
        )

      assert Calendar.next_event(~U[2030-07-24 01:59:00Z]).id == fest.id
      assert Calendar.next_event(~U[2030-07-24 02:00:00Z]) == nil
    end
  end

  describe "reminders and deletion" do
    test "a due reminder on a visible item fires and links to the item" do
      fest = festival_fixture()

      item =
        programme_item_fixture(fest,
          slug: "gottesdienst",
          reminders: [%{lead_days: 1, text: "Morgen!"}]
        )

      draft =
        programme_item_fixture(fest, status: "draft", reminders: [%{lead_days: 1, text: "x"}])

      assert [reminder] = Calendar.due_reminders(~U[2030-07-20 12:00:00Z])
      assert reminder.event.id == item.id
      refute reminder.event.id == draft.id

      assert Bbh.Calendar.Paths.path(reminder.event) == "/termine/2030/#{fest.slug}#gottesdienst"
    end

    test "deleting a festival deletes its items and their reminders" do
      fest = festival_fixture()
      item = programme_item_fixture(fest, reminders: [%{lead_days: 1, text: "Morgen!"}])

      {:ok, _} = Calendar.delete_event(fest)

      refute Repo.get(Event, item.id)
      assert Repo.aggregate(EventReminder, :count, :id) == 0
    end
  end

  describe "block_event_options/2" do
    test "festivals first, then by date; no items, no internal calendars, nothing stale" do
      now = ~U[2030-01-01 12:00:00Z]
      fest = festival_fixture()
      programme_item_fixture(fest)
      programme_item_fixture(fest, status: "draft")
      single = event_fixture(title: "Königsball", starts_at: ~U[2030-03-01 19:00:00Z])
      draft = event_fixture(status: "draft", starts_at: ~U[2030-04-01 19:00:00Z])
      event_fixture(calendar: "vorstand", starts_at: ~U[2030-03-02 19:00:00Z])
      stale = event_fixture(starts_at: ~U[2029-01-01 19:00:00Z])

      assert [f, s, d] = Calendar.block_event_options(now)
      assert {f.id, f.child_count} == {fest.id, 2}
      assert {s.id, d.id} == {single.id, draft.id}

      included = Calendar.block_event_options(now, include: stale.id)
      assert stale.id in Enum.map(included, & &1.id)

      assert [%{id: id}] = Calendar.block_event_options(now, query: "könig")
      assert id == single.id
    end
  end

  describe "get_public_event_by_id/1" do
    test "a public festival with its visible items; nothing for drafts, items, junk" do
      fest = festival_fixture()
      item = programme_item_fixture(fest)
      programme_item_fixture(fest, status: "draft")

      assert %Event{children: [child]} = Calendar.get_public_event_by_id(fest.id)
      assert child.id == item.id

      assert Calendar.get_public_event_by_id(item.id) == nil
      assert Calendar.get_public_event_by_id(event_fixture(status: "draft").id) == nil
      assert Calendar.get_public_event_by_id("nope") == nil
      assert Calendar.get_public_event_by_id(nil) == nil
    end
  end
end
