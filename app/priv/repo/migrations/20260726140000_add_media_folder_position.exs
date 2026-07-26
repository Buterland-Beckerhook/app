defmodule Bbh.Repo.Migrations.AddMediaFolderPosition do
  use Ecto.Migration

  # Folders used to sort alphabetically by name, hard-wired into every query. An
  # explicit position lets an editor drag them into the order the club thinks in
  # ("Aktuelles" before "Archiv 2019"), which alphabetical order can never express.
  def up do
    alter table(:media_folders) do
      add :position, :integer, null: false, default: 0
    end

    # Freeze today's alphabetical order into the new column, per parent level, so
    # nothing jumps around on deploy. Without this every folder would sit at 0 and
    # the tie-break on name would be the only thing left ordering them.
    execute """
    UPDATE media_folders f
    SET position = ranked.rn
    FROM (
      SELECT id, row_number() OVER (PARTITION BY parent_id ORDER BY name) - 1 AS rn
      FROM media_folders
    ) ranked
    WHERE f.id = ranked.id
    """

    # Deliberately NOT a unique index on (parent_id, position): reordering renumbers
    # the siblings row by row inside a transaction, so two rows briefly share a value.
    # Same constraint as page_blocks.position and block_gallery_files.sort — see the
    # comment above Bbh.Ordering.renumber/2.
    create index(:media_folders, [:parent_id, :position])
  end

  def down do
    drop index(:media_folders, [:parent_id, :position])

    alter table(:media_folders) do
      remove :position
    end
  end
end
