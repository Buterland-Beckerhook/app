defmodule Bbh.Workers.TicketReminder do
  @moduledoc """
  The Postfach's daily mails: reminders to the people who should act
  (`Bbh.Tickets.Reminders`) — at most one per person and day — and the admin digest.

  Runs hourly; sends once the local hour reaches `ticket_reminder_hour` (site settings,
  tab "Postfach"), and only once per day: `Bbh.Settings.claim_ticket_reminders/1` marks
  the day before anything goes out. A run that was missed at that hour (deploy, restart)
  is made up by the next one the same day.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  import Ecto.Query

  alias Bbh.Accounts.User
  alias Bbh.Repo
  alias Bbh.Settings
  alias Bbh.Tickets.{Notifier, Reminders, Ticket}

  @impl Oban.Worker
  def perform(_job) do
    settings = Settings.get()
    local = Bbh.Time.real_now()

    if local.hour >= settings.ticket_reminder_hour and
         Settings.claim_ticket_reminders(DateTime.to_date(local)) do
      send_reminders(settings)
      if settings.ticket_admin_digest_enabled, do: send_digest(settings)
    end

    :ok
  end

  defp send_reminders(settings) do
    due = Reminders.due(settings)
    users = Repo.all(from u in User, where: u.id in ^Map.keys(due)) |> Map.new(&{&1.id, &1})

    for {user_id, items} <- due, user = users[user_id] do
      Notifier.reminders(user, items)
    end
  end

  # Admins get no per-ticket mails for queues they don't work; this is their overview.
  # Skipped on a day without anything overdue or escalated.
  defp send_digest(settings) do
    overdue = Ticket |> Reminders.overdue(settings) |> order_by([t], t.number) |> Repo.all()
    escalations = Reminders.escalations(settings)

    if overdue != [] or escalations != [] do
      digest = %{counts: counts(), overdue: overdue, escalations: escalations}

      for admin <- Repo.all(from u in User, where: u.role == "admin") do
        Notifier.digest(admin, digest)
      end
    end
  end

  defp counts do
    Repo.all(
      from t in Ticket,
        where: is_nil(t.deleted_at) and t.status in ^Ticket.active_statuses(),
        group_by: [t.queue, t.status],
        select: {t.queue, t.status, count(t.id)}
    )
    |> Enum.reduce(%{}, fn {queue, status, n}, acc ->
      Map.update(acc, queue, %{status => n}, &Map.put(&1, status, n))
    end)
  end
end
