defmodule Bbh.Repo.Migrations.CreateCalendarShares do
  use Ecto.Migration

  def change do
    create table(:calendar_shares, primary_key: false) do
      add :id, :binary_id, primary_key: true
      # Internal calendar being shared: vorstand|offiziere|jungschuetzen|kinderfest.
      add :calendar, :string, null: false
      # SHA-256 hash of the token; the plaintext is only ever handed to the recipient.
      add :token, :binary, null: false
      add :recipient_label, :string
      add :revoked_at, :utc_datetime
      add :last_used_at, :utc_datetime
      add :expires_at, :utc_datetime
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:calendar_shares, [:token])
    create index(:calendar_shares, [:calendar])
    create index(:calendar_shares, [:created_by_id])
  end
end
