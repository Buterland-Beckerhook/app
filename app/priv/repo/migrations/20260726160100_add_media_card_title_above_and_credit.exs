defmodule Bbh.Repo.Migrations.AddMediaCardTitleAboveAndCredit do
  use Ecto.Migration

  def change do
    alter table(:block_media_card) do
      add :title_above, :boolean, null: false, default: false
      add :show_credit, :boolean, null: false, default: false
    end
  end
end
