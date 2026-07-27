defmodule Bbh.Workers.EventPublishNotifier do
  @moduledoc """
  Sends the "Neuer Termin" web-push once a public event is published.

  Runs on a cron (every five minutes). `notify/1` is also called directly
  (off-request) by the event form for an instant push when publishing now; the
  cron is the safety net that also delivers anything held back overnight.

  Idempotent: each event is pushed at most once, guarded by `Event.notified_at`.
  Mirrors `Bbh.Workers.ArticlePublishNotifier`.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias Bbh.Calendar
  alias Bbh.Calendar.Event

  @impl Oban.Worker
  def perform(_job) do
    for event <- Calendar.events_pending_notification(), do: notify(event)
    :ok
  end

  @doc """
  Push the publish notification for one event and mark it as notified.

  During quiet hours nothing is sent and the event is left unmarked, so the next
  cron tick after the window ends picks it up (self-healing).
  """
  def notify(%Event{} = event) do
    if Bbh.Settings.quiet_now?() do
      :ok
    else
      # Mark first so a retry after a crash mid-send doesn't double-notify.
      {:ok, event} = Calendar.mark_event_notified(event)

      url = BbhWeb.Endpoint.url() <> "/termine/#{event.year}/#{event.slug}"
      Bbh.Notifications.notify("termine", %{title: "Neuer Termin", body: event.title, url: url})

      :ok
    end
  end
end
