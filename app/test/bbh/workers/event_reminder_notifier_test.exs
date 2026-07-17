defmodule Bbh.Workers.EventReminderNotifierTest do
  use Bbh.DataCase, async: true

  import Bbh.CalendarFixtures

  alias Bbh.Calendar
  alias Bbh.Calendar.EventReminder
  alias Bbh.Workers.EventReminderNotifier

  defp from_now(n), do: Bbh.Time.now() |> DateTime.add(n, :day) |> DateTime.truncate(:second)

  test "perform sends each due reminder once and marks it sent" do
    event = event_fixture(starts_at: from_now(2), reminders: [%{lead_days: 10, text: "Gleich!"}])

    assert :ok = EventReminderNotifier.perform(%Oban.Job{})

    reminder = Repo.get_by!(EventReminder, event_id: event.id)
    assert reminder.sent_at

    # No longer due; a second run is a no-op.
    assert Calendar.due_reminders() == []
    assert :ok = EventReminderNotifier.perform(%Oban.Job{})
  end

  test "perform leaves not-yet-due reminders untouched" do
    event = event_fixture(starts_at: from_now(30), reminders: [%{lead_days: 3, text: "Später"}])

    assert :ok = EventReminderNotifier.perform(%Oban.Job{})

    reminder = Repo.get_by!(EventReminder, event_id: event.id)
    refute reminder.sent_at
  end
end
