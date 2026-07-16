defmodule Bbh.Repo.Migrations.AddEmailToPeople do
  use Ecto.Migration

  def change do
    alter table(:people) do
      add :email, :string
    end
  end
end
