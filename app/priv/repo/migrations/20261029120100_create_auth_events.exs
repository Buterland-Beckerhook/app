defmodule Bbh.Repo.Migrations.CreateAuthEvents do
  use Ecto.Migration

  # Login log for the admin area (Bbh.Accounts.AuthLog). user_id is nil for attempts that
  # name no known account; the e-mail address typed in is deliberately not stored.
  def change do
    create table(:auth_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :event, :string, null: false
      add :method, :string
      add :ip, :string
      add :user_agent, :string
      add :inserted_at, :utc_datetime, null: false, default: fragment("now()")
    end

    create index(:auth_events, [:user_id, :inserted_at])
    create index(:auth_events, [:inserted_at])
  end
end
