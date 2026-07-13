defmodule Bbh.Repo.Migrations.CreatePeople do
  use Ecto.Migration

  def change do
    create table(:people, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :role, :string, null: false
      add :honorary_member, :boolean, null: false, default: false
      add :street, :string
      add :city, :string
      add :birth_date, :string
      add :death_date, :string
      add :year_start, :integer
      add :year_end, :integer
      add :biography, :text
      add :portrait_id, references(:media, type: :binary_id, on_delete: :nilify_all)
      add :sort_order, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:people, [:role, :sort_order])
    create constraint(:people, :people_sort_order_nonneg, check: "sort_order >= 0")
  end
end
