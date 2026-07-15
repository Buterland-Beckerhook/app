defmodule Bbh.Repo.Migrations.CreateUserPasskeys do
  use Ecto.Migration

  def change do
    create table(:users_passkeys, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :credential_id, :binary, null: false
      add :public_key, :binary, null: false
      add :aaguid, :binary
      add :sign_count, :integer, null: false, default: 0
      add :nickname, :string, null: false
      add :last_used_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users_passkeys, [:credential_id])
    create index(:users_passkeys, [:user_id])
  end
end
