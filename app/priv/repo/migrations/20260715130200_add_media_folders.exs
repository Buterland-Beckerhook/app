defmodule Bbh.Repo.Migrations.AddMediaFolders do
  use Ecto.Migration

  # Two-level folder tree for organising the media library. Deleting a folder
  # nilifies its media's folder_id (media move back to "unfiled"), and deleting a
  # top-level folder cascades to its sub-folders.
  def change do
    create table(:media_folders, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false

      add :parent_id,
          references(:media_folders, type: :binary_id, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    # Names are unique within their parent (NULL parent = top level). Postgres treats
    # NULLs as distinct, so a partial index enforces uniqueness among top-level folders.
    create unique_index(:media_folders, [:parent_id, :name],
             where: "parent_id IS NOT NULL",
             name: :media_folders_parent_name_index
           )

    create unique_index(:media_folders, [:name],
             where: "parent_id IS NULL",
             name: :media_folders_root_name_index
           )

    alter table(:media) do
      add :folder_id,
          references(:media_folders, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:media, [:folder_id])
  end
end
