defmodule Bbh.Repo.Migrations.AddPersonListOnlyActiveAndDropCompact do
  use Ecto.Migration

  @moduledoc """
  Two changes to the Personenliste block.

  `only_active` restricts the list to people still in office. „Amt bis" (`year_end`) being
  empty is the only signal the data carries for that — the same one `Bbh.Club.role_holder/1`
  already orders by; `death_date` is free text and cannot be compared.

  „Kompakt" leaves `PersonList.styles/0` in the same commit. It was offered by the editor,
  stored, validated — and then never read by the renderer, which always drew the table. A
  row left on the removed value would start failing `validate_inclusion` on the editor's
  next save, so existing ones are normalised to „Tabelle" (what they in fact rendered as).

  `down` restores neither: a rollback is not a restore.
  """

  def up do
    alter table(:block_person_list) do
      add :only_active, :boolean, null: false, default: false
    end

    execute "UPDATE block_person_list SET display_style = 'table' WHERE display_style = 'compact'"
  end

  def down do
    alter table(:block_person_list) do
      remove :only_active
    end
  end
end
