defmodule Bbh.Repo.Migrations.CreateEventReminders do
  use Ecto.Migration

  def change do
    create table(:event_reminders, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event_id, references(:events, type: :binary_id, on_delete: :delete_all), null: false
      add :lead_days, :integer, null: false
      add :text, :string, null: false
      add :sent_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:event_reminders, [:event_id])
    # Partial index: the notifier only ever scans reminders not yet sent.
    create index(:event_reminders, [:sent_at], where: "sent_at IS NULL")
  end
end
