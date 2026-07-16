defmodule Bbh.Repo.Migrations.AddPageNavigation do
  use Ecto.Migration

  def change do
    alter table(:pages) do
      add :show_in_menu, :boolean, null: false, default: true
    end

    # Legal pages keep their own fixed routes and must not appear in the
    # dynamic "Verein" navigation tree.
    execute(
      "UPDATE pages SET show_in_menu = false WHERE slug IN ('impressum', 'datenschutz')",
      "SELECT 1"
    )
  end
end
