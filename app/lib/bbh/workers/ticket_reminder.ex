defmodule Bbh.Workers.TicketReminder do
  @moduledoc """
  The Postfach's daily admin digest. The reminders themselves travel with each user's
  notifications (`Bbh.Tickets.Alerts`).

  Runs hourly; sends once the local hour reaches `ticket_reminder_hour` (site settings,
  tab "Postfach"), and only once per day: `Bbh.Settings.claim_ticket_reminders/1` marks
  the day before anything goes out. A run that was missed at that hour (deploy, restart)
  is made up by the next one the same day. Quiet hours hold it back the same way.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias Bbh.Settings
  alias Bbh.Tickets.{Notifier, Reminders}

  @impl Oban.Worker
  def perform(_job) do
    settings = Settings.get()
    local = Bbh.Time.real_now()

    if local.hour >= settings.ticket_reminder_hour and not Settings.quiet_now?(local) and
         Settings.claim_ticket_reminders(DateTime.to_date(local)) do
      if settings.ticket_admin_digest_enabled, do: send_digest(settings)
    end

    :ok
  end

  # Admins get no per-ticket mails for queues they don't work; this is their overview.
  # Skipped on a day without anything overdue or escalated.
  defp send_digest(settings) do
    overdue = Reminders.overdue_tickets(settings)
    escalations = Reminders.escalations(settings)

    if overdue != [] or escalations != [] do
      digest = %{counts: Reminders.active_counts(), overdue: overdue, escalations: escalations}

      for admin <- Bbh.Accounts.list_admins() do
        Notifier.digest(admin, digest)
      end
    end
  end
end
