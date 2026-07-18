defmodule Bbh.Repo.Migrations.MakeThroneQueenNullable do
  use Ecto.Migration

  # King-only thrones (e.g. Jungschützenkönig) have no queen.
  def up do
    alter table(:thrones) do
      modify :queen, :string, null: true
    end
  end

  def down do
    alter table(:thrones) do
      modify :queen, :string, null: false
    end
  end
end
