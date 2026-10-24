defmodule Bbh.Workers.EventPublishNotifier do
  @moduledoc """
  Sends the "Neuer Termin" web-push for newly published public events — bundled.

  Events tend to be published in bulk: the whole year's programme right after the
  Jahreshauptversammlung, nine or so within minutes. One push per event would ring
  every subscriber's phone nine times, so the push waits until publishing has
  settled — no pending event touched for 30 minutes — and then sends **one**
  push for all of them: "Neuer Termin: <Titel>" for a single event, "N neue Termine"
  with the first titles otherwise.

  Runs on a cron (every five minutes); there is no immediate push from the form.
  Self-healing: pending = published, public, upcoming, `notified_at` unset (see
  `Bbh.Calendar.events_pending_notification/1`), so editing or unpublishing an event
  before the push simply changes what goes out. During quiet hours nothing is sent
  and the events stay unmarked for the next tick after the window.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias Bbh.Calendar

  # Minutes without a change to any pending event before the bundle goes out.
  @settle_minutes 30
  # Titles named in a bundled push before "und N weitere".
  @named_titles 3

  @impl Oban.Worker
  def perform(_job) do
    deliver_pending(DateTime.utc_now())
    :ok
  end

  @doc """
  Send the bundled push for everything pending, if publishing has settled by
  `utc_now` (`updated_at` is real UTC). Returns `:sent`, `:waiting` or `:none`.
  """
  def deliver_pending(utc_now) do
    case Calendar.events_pending_notification() do
      [] ->
        :none

      events ->
        cond do
          not settled?(events, utc_now) -> :waiting
          Bbh.Settings.quiet_now?() -> :waiting
          true -> send_bundle(events)
        end
    end
  end

  defp settled?(events, utc_now) do
    latest = events |> Enum.map(& &1.updated_at) |> Enum.max(DateTime)
    DateTime.diff(utc_now, latest, :minute) >= @settle_minutes
  end

  defp send_bundle(events) do
    # Mark first so a retry after a crash mid-send doesn't double-notify.
    Enum.each(events, &({:ok, _} = Calendar.mark_event_notified(&1)))
    Bbh.Notifications.notify("termine", payload(events))
    :sent
  end

  @doc "The push for a set of newly published events (chronological, as pending)."
  def payload([event]) do
    %{title: "Neuer Termin", body: event.title, url: BbhWeb.EventPaths.url(event)}
  end

  def payload(events) do
    {named, rest} = Enum.split(events, @named_titles)
    titles = Enum.map_join(named, ", ", & &1.title)
    body = if rest == [], do: titles, else: "#{titles} und #{length(rest)} weitere"

    %{
      title: "#{length(events)} neue Termine",
      body: body,
      url: BbhWeb.Endpoint.url() <> list_path(events)
    }
  end

  # The /termine year of the bundle when it is a single one (the list defaults to the
  # current year, which a bundle published in December for next year would miss).
  defp list_path(events) do
    case events |> Enum.map(& &1.year) |> Enum.uniq() do
      [year] -> "/termine?jahr=#{year}"
      _ -> "/termine"
    end
  end
end
