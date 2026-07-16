defmodule Bbh.Repo.Migrations.CreateMedia do
  use Ecto.Migration

  # Uploaded files (the directus_files equivalent). Originals live in the uploads
  # volume under `storage_key`; responsive variants are derived on demand (Task 4).
  def change do
    create table(:media, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :storage_key, :string, null: false
      add :filename, :string, null: false
      add :content_type, :string
      add :byte_size, :bigint
      add :width, :integer
      add :height, :integer
      add :focal_point_x, :float
      add :focal_point_y, :float
      add :title, :string
      add :description, :string
      add :copyright, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:media, [:storage_key])
  end
end
