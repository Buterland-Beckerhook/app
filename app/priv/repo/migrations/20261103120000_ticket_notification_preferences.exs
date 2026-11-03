defmodule Bbh.Repo.Migrations.TicketNotificationPreferences do
  use Ecto.Migration

  # Postfach notifications per user (Bbh.Tickets.Alerts): how often and over which
  # channel, a per-user outbox instead of one marker per ticket, and the owner of a push
  # device. The outbox holds ids only, like Oban args: no personal data.
  def change do
    alter table(:users) do
      add :ticket_notify_interval_minutes, :integer, null: false, default: 2
      add :ticket_notify_channel, :string, null: false, default: "mail"
      add :ticket_reminded_on, :date
    end

    # At least once a day: a request must not wait longer because of a setting.
    create constraint(:users, :users_ticket_notify_interval_valid,
             check: "ticket_notify_interval_minutes BETWEEN 2 AND 1440"
           )

    create constraint(:users, :users_ticket_notify_channel_valid,
             check: "ticket_notify_channel IN ('mail', 'push', 'both')"
           )

    create table(:ticket_notifications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :ticket_id, references(:tickets, type: :binary_id, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:ticket_notifications, [:user_id, :ticket_id, :kind])
    create index(:ticket_notifications, [:ticket_id])

    # A browser has exactly one push subscription per site, so a device that gets Postfach
    # notifications is the same row as its public one. Deleting the user keeps the public
    # part; Bbh.Notifications.prune_orphans/0 sweeps a row left with nothing.
    alter table(:push_subscriptions) do
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:push_subscriptions, [:user_id], where: "user_id IS NOT NULL")
  end
end
