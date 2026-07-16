defmodule Bbh.Repo.Migrations.AddRoleAndTotpToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :role, :string, null: false, default: "editor"
      # TOTP second factor: secret bytes + when it was confirmed/enabled.
      add :totp_secret, :binary
      add :totp_confirmed_at, :utc_datetime
    end

    create constraint(:users, :users_role_valid, check: "role IN ('admin', 'editor')")
  end
end
