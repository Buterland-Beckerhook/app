defmodule Bbh.Repo.Migrations.CreateBlockSeparator do
  use Ecto.Migration

  # A field-less content block: a horizontal rule between other blocks. The row
  # exists only so the polymorphic page_blocks link has something to point at.
  def change do
    create table(:block_separator, primary_key: false) do
      add :id, :binary_id, primary_key: true
      timestamps(type: :utc_datetime)
    end
  end
end
