defmodule Bbh.Repo.Migrations.EventProgramme do
  @moduledoc """
  Parent/child events (a festival and its programme items):

    * deleting a festival deletes its programme (was: orphaned the items);
    * slugs are unique per year among top-level events, and per parent among
      programme items — every Schützenfest can have its own "gottesdienst" without
      colliding with a standalone "Gottesdienst" the same year.

  The top-level index keeps the name `events_slug_year_unique` so the schema's
  `unique_constraint` keeps matching it.
  """
  use Ecto.Migration

  def up do
    alter table(:events) do
      modify :parent_id, references(:events, type: :binary_id, on_delete: :delete_all),
        from: references(:events, type: :binary_id, on_delete: :nilify_all)
    end

    drop index(:events, [:slug, :year], name: :events_slug_year_unique)

    create unique_index(:events, [:slug, :year],
             name: :events_slug_year_unique,
             where: "parent_id IS NULL"
           )

    create unique_index(:events, [:parent_id, :slug],
             name: :events_parent_slug_unique,
             where: "parent_id IS NOT NULL"
           )
  end

  def down do
    drop index(:events, [:parent_id, :slug], name: :events_parent_slug_unique)
    drop index(:events, [:slug, :year], name: :events_slug_year_unique)
    create unique_index(:events, [:slug, :year], name: :events_slug_year_unique)

    alter table(:events) do
      modify :parent_id, references(:events, type: :binary_id, on_delete: :nilify_all),
        from: references(:events, type: :binary_id, on_delete: :delete_all)
    end
  end
end
