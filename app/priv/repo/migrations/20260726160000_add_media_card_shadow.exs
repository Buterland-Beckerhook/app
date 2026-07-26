defmodule Bbh.Repo.Migrations.AddMediaCardShadow do
  use Ecto.Migration

  def change do
    alter table(:block_media_card) do
      add :shadow, :boolean, null: false, default: false
    end
  end
end
