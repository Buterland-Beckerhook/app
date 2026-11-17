defmodule Bbh.Workers.TicketNewNotifier do
  @moduledoc """
  Tells the users granted a queue about new Postfach tickets — bundled: a ticket waits
  two minutes, then goes into the outbox of everyone working its queue. Each run also
  sends what is due from that outbox, new tickets and replies alike, by each user's own
  interval and channel (`Bbh.Tickets.Alerts`).

  Cron plus a marker column (`tickets.notified_at`), like the other notifiers: each run
  picks the due, unannounced tickets, so a missed run is repaired by the next. A ticket
  someone took within the two minutes, or one marked as spam, is not announced; spam
  taken back counts as new again. A queue nobody is granted goes to the admins.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias Bbh.Tickets.Alerts

  @delay_minutes 2

  @impl Oban.Worker
  def perform(_job) do
    DateTime.utc_now(:second)
    |> DateTime.add(-@delay_minutes, :minute)
    |> Alerts.enqueue_due_new()

    Alerts.flush()
    :ok
  end
end
