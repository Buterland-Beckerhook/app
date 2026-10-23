defmodule Bbh.Repo.Migrations.AddPagePlacement do
  use Ecto.Migration

  # Replaces the `show_in_menu` flag with an explicit `placement`:
  #
  #   * "menu"     — top-level page in the "Verein" menu, served under /verein/*path
  #   * "unlisted" — top-level page outside the menu, served under /seite/:slug and
  #                  reachable only via links (e.g. from an event or article)
  #   * "system"   — embedded by the application itself (Impressum, Datenschutz,
  #                  the membership-form snippets); never served on its own generic route
  #
  # Until now every top-level page with `show_in_menu = false` was one of the system
  # pages (nothing else could reach it), so that is what they become. Child pages
  # inherit their root's placement; theirs is normalized to "menu".
  #
  # `noindex` keeps a page out of search engines (X-Robots-Tag), the sitemap and the
  # on-site search.
  def up do
    alter table(:pages) do
      add :placement, :string, null: false, default: "menu"
      add :noindex, :boolean, null: false, default: false
    end

    execute(
      "UPDATE pages SET placement = 'system' WHERE parent_id IS NULL AND show_in_menu = false"
    )

    alter table(:pages) do
      remove :show_in_menu
    end
  end

  def down do
    alter table(:pages) do
      add :show_in_menu, :boolean, null: false, default: true
    end

    execute("UPDATE pages SET show_in_menu = false WHERE placement <> 'menu'")

    alter table(:pages) do
      remove :placement
      remove :noindex
    end
  end
end
