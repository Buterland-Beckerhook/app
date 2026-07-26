defmodule Bbh.Repo.Migrations.AddPersonListSortBy do
  use Ecto.Migration

  @moduledoc """
  Adds `sort_by` to the Personenliste block so a block can choose its ordering:
  „Reihenfolge (manuell)" (`sort_order`) — the previous, fixed behaviour and the default —
  or „Amtsantritt (Jahr)" (`Person.year_start`).

  `down` drops the column: a rollback is not a restore.
  """

  def up do
    alter table(:block_person_list) do
      add :sort_by, :string, null: false, default: "sort_order"
    end
  end

  def down do
    alter table(:block_person_list) do
      remove :sort_by
    end
  end
end
