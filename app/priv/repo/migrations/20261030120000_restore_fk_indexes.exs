defmodule Bbh.Repo.Migrations.RestoreFkIndexes do
  use Ecto.Migration

  # The 2026-07-13 migrations create these, but at least one database (bbh_dev) was
  # found without them, most likely after a dump restore. Recreate any that are
  # missing; a no-op where they exist.
  def up do
    create_if_not_exists index(:people, [:portrait_id])
    create_if_not_exists index(:events, [:location_id])
    create_if_not_exists index(:events, [:image_id])
    create_if_not_exists index(:block_gallery_files, [:media_id])
    create_if_not_exists index(:block_media_card, [:image_id])
  end

  # The indexes belong to the original migrations; rolling this one back must not
  # drop them.
  def down, do: :ok
end
