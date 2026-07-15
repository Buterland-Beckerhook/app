defmodule Bbh.Repo.Migrations.DropHashedPasswordFromUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      remove :hashed_password, :string
    end
  end
end
