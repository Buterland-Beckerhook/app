defmodule Bbh.Repo.Migrations.AddScheduledAtToEventReminders do
  use Ecto.Migration

  def up do
    alter table(:event_reminders) do
      # A reminder is now either relative (lead_days) or absolute (scheduled_at).
      add :scheduled_at, :utc_datetime
      # Text is optional; the notifier falls back to the event title.
      modify :text, :string, null: true
    end

    # lead_days becomes optional (absolute reminders leave it null).
    execute("ALTER TABLE event_reminders ALTER COLUMN lead_days DROP NOT NULL")

    # Exactly one scheduling mode must be set.
    create constraint(:event_reminders, :event_reminders_one_schedule,
             check: "(lead_days IS NOT NULL) <> (scheduled_at IS NOT NULL)"
           )
  end

  def down do
    drop constraint(:event_reminders, :event_reminders_one_schedule)

    execute("UPDATE event_reminders SET lead_days = 0 WHERE lead_days IS NULL")
    execute("ALTER TABLE event_reminders ALTER COLUMN lead_days SET NOT NULL")
    execute("UPDATE event_reminders SET text = '' WHERE text IS NULL")

    alter table(:event_reminders) do
      modify :text, :string, null: false
      remove :scheduled_at
    end
  end
end
