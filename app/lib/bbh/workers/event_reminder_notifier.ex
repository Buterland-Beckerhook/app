defmodule Bbh.Workers.EventReminderNotifier do
  @moduledoc """
  Sends per-event push reminders once their lead time is reached.

  Runs on a cron (every five minutes). Due-ness is computed from the event's
  current `starts_at`, so rescheduling an event shifts its reminders
  automatically; canceling, un-publishing, or deleting the event stops them
  (the last via the `on_delete: :delete_all` FK). Each reminder is sent at most
  once, guarded by `EventReminder.sent_at`.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias Bbh.Calendar
  alias Bbh.Calendar.EventReminder

  @impl Oban.Worker
  def perform(_job) do
    for reminder <- Calendar.due_reminders(), do: notify(reminder)
    :ok
  end

  @doc "Deliver one reminder's push and mark it as sent."
  def notify(%EventReminder{event: event} = reminder) do
    # Mark first so a retry after a crash mid-send doesn't double-notify.
    {:ok, _} = Calendar.mark_reminder_sent(reminder)

    url = BbhWeb.Endpoint.url() <> "/termine/#{event.year}/#{event.slug}"
    Bbh.Notifications.notify("termine", %{title: event.title, body: reminder.text, url: url})

    :ok
  end
end
