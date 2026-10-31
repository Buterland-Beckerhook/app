defmodule Bbh.Repo.Migrations.AddTotpLastStepToUsers do
  use Ecto.Migration

  # The 30 s period (Unix time div 30) of the last TOTP code accepted for the user, so a
  # code can't be accepted twice (Bbh.Accounts.use_user_totp/3).
  def change do
    alter table(:users) do
      add :totp_last_step, :bigint
    end
  end
end
