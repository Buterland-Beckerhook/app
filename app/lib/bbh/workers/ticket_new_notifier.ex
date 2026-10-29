defmodule Bbh.Workers.TicketNewNotifier do
  @moduledoc """
  Tells the users granted a queue about new Postfach tickets — bundled: a ticket waits
  two minutes, then everyone gets one mail listing all new tickets of their queues.

  Cron plus a marker column (`tickets.notified_at`), like the other notifiers: each run
  picks the due, unannounced tickets, so a missed run is repaired by the next. A ticket
  someone took within the two minutes, or one marked as spam, is not announced; spam
  taken back counts as new again. A queue nobody is granted goes to the admins.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  import Ecto.Query

  alias Bbh.Repo
  alias Bbh.Tickets.{Grants, Notifier, Ticket}

  @delay_minutes 2

  @impl Oban.Worker
  def perform(_job) do
    cutoff = DateTime.utc_now(:second) |> DateTime.add(-@delay_minutes, :minute)

    tickets =
      Repo.all(
        from t in Ticket,
          where:
            is_nil(t.notified_at) and is_nil(t.deleted_at) and t.status == "new" and
              t.inserted_at <= ^cutoff,
          order_by: t.number
      )

    # Mark first: a crash mid-way must not announce the same ticket twice.
    {_, _} =
      Repo.update_all(
        from(t in Ticket, where: t.id in ^Enum.map(tickets, & &1.id) and is_nil(t.notified_at)),
        set: [notified_at: DateTime.utc_now(:second)]
      )

    tickets
    |> Enum.flat_map(fn ticket ->
      for user <- Grants.notify_users(ticket.queue), do: {user, ticket}
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.each(fn {user, tickets} -> Notifier.new_tickets(user, tickets) end)

    :ok
  end
end
