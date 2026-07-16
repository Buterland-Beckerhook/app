defmodule Bbh.Repo.Migrations.CreateLocations do
  use Ecto.Migration

  def change do
    create table(:locations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string, null: false
      add :name, :string, null: false
      add :street, :string
      add :zip, :string
      add :city, :string
      add :lat, :float
      add :lng, :float
      add :url, :string
      add :maps_url, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:locations, [:key])
  end
end
