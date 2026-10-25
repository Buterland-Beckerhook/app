defmodule Bbh.Repo.Migrations.CreateTrophies do
  use Ecto.Migration

  # Pokale and their winners per year (docs/content-plan.md §1.1), plus the „Pokalsieger"
  # content block that renders them. Winners are plain names, like `thrones` — no link
  # to `people`, which only holds office bearers.
  def change do
    create table(:trophies, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :since, :integer
      add :description, :text
      add :sort_order, :integer, null: false, default: 0
      timestamps()
    end

    create unique_index(:trophies, [:name])

    create table(:trophy_wins, primary_key: false) do
      add :id, :binary_id, primary_key: true
      # A trophy with winners cannot be deleted by accident; its history goes with it.
      add :trophy_id, references(:trophies, type: :binary_id, on_delete: :restrict), null: false

      add :year, :integer, null: false
      add :winner, :string, null: false
      add :rings, :integer
      add :note, :string
      timestamps()
    end

    # One winner per trophy and year — the table is year × trophy.
    create unique_index(:trophy_wins, [:trophy_id, :year])
    create index(:trophy_wins, [:year])

    create constraint(:trophy_wins, :trophy_wins_year_range, check: "year >= 1900")

    create constraint(:trophy_wins, :trophy_wins_rings_positive,
             check: "rings IS NULL OR rings > 0"
           )

    create table(:block_trophy_table, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string
      add :show_records, :boolean, null: false, default: true
      add :show_descriptions, :boolean, null: false, default: false
      timestamps()
    end
  end
end
