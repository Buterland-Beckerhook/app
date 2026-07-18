defmodule Bbh.CalendarRemindersTest do
  use Bbh.DataCase, async: true

  alias Bbh.Calendar
  alias Bbh.Calendar.EventReminder

  import Bbh.CalendarFixtures

  defp from_now(n), do: Bbh.Time.now() |> DateTime.add(n, :day) |> DateTime.truncate(:second)

  describe "reminders via cast_assoc" do
    test "an event can be created with reminders" do
      {:ok, event} =
        Calendar.create_event(%{
          status: "published",
          title: "Schützenfest",
          slug: "fest-#{System.unique_integer([:positive])}",
          starts_at: from_now(20),
          reminders: [%{lead_days: 14, text: "In zwei Wochen!"}, %{lead_days: 3, text: "Bald!"}]
        })

      event = Calendar.get_event!(event.id)
      # Preloaded newest lead first.
      assert Enum.map(event.reminders, & &1.lead_days) == [14, 3]
    end

    test "deleting an event removes its reminders (FK cascade)" do
      event = event_fixture(starts_at: from_now(20), reminders: [%{lead_days: 5, text: "Hallo"}])
      assert Repo.aggregate(EventReminder, :count, :id) == 1

      {:ok, _} = Calendar.delete_event(Calendar.get_event!(event.id))
      assert Repo.aggregate(EventReminder, :count, :id) == 0
    end

    test "lead_days is validated" do
      {:error, changeset} =
        Calendar.create_event(%{
          status: "published",
          title: "T",
          slug: "t-#{System.unique_integer([:positive])}",
          starts_at: from_now(5),
          reminders: [%{lead_days: -1, text: "x"}]
        })

      refute changeset.valid?
    end
  end

  describe "due_reminders/1" do
    test "returns reminders whose lead time has been reached for a public upcoming event" do
      event = event_fixture(starts_at: from_now(2), reminders: [%{lead_days: 10, text: "Los!"}])
      [reminder] = Calendar.due_reminders()
      assert reminder.event.id == event.id
      assert reminder.text == "Los!"
    end

    test "excludes reminders whose lead time is not yet reached" do
      event_fixture(starts_at: from_now(30), reminders: [%{lead_days: 3, text: "Zu früh"}])
      assert Calendar.due_reminders() == []
    end

    test "excludes already-sent reminders" do
      event_fixture(starts_at: from_now(2), reminders: [%{lead_days: 10, text: "x"}])
      [reminder] = Calendar.due_reminders()
      {:ok, _} = Calendar.mark_reminder_sent(reminder)
      assert Calendar.due_reminders() == []
    end

    test "excludes reminders for canceled, unannounced, internal, or past events" do
      event_fixture(
        status: "canceled",
        starts_at: from_now(2),
        reminders: [%{lead_days: 9, text: "x"}]
      )

      event_fixture(
        announce: false,
        starts_at: from_now(2),
        reminders: [%{lead_days: 9, text: "x"}]
      )

      event_fixture(
        calendar: "vorstand",
        starts_at: from_now(2),
        reminders: [%{lead_days: 9, text: "x"}]
      )

      event_fixture(starts_at: from_now(-1), reminders: [%{lead_days: 9, text: "x"}])

      assert Calendar.due_reminders() == []
    end
  end
end
