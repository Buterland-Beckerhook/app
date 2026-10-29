defmodule Bbh.Repo.Migrations.TicketNotifications do
  use Ecto.Migration

  # Postfach notifications (Bbh.Workers.TicketNewNotifier / TicketReminder): a marker per
  # ticket for "queue told about it", the reminder/escalation settings on the site
  # settings singleton, and the day the reminders last went out.
  def change do
    alter table(:tickets) do
      add :notified_at, :utc_datetime
    end

    # Tickets that exist already are not news to anyone.
    execute "UPDATE tickets SET notified_at = now()", ""

    create index(:tickets, [:notified_at], where: "notified_at IS NULL")

    alter table(:site_settings) do
      add :ticket_reminder_hour, :integer, null: false, default: 8
      add :ticket_remind_unassigned_hours, :integer, null: false, default: 24
      add :ticket_remind_idle_days, :integer, null: false, default: 7
      add :ticket_remind_waiting_days, :integer, null: false, default: 14
      add :ticket_escalate_days, :integer, null: false, default: 3
      add :ticket_admin_digest_enabled, :boolean, null: false, default: true
      add :ticket_reminders_sent_on, :date
    end
  end
end
