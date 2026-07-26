defmodule Bbh.Repo.Migrations.AddGallerySlideshowOptions do
  use Ecto.Migration

  # The "Diashow" layout has been selectable since the block was created but never had
  # anything of its own to configure. A slideshow needs a frame all its images share —
  # without one every photo keeps its own ratio and the box jumps between slides — and
  # a diashow that never advances by itself is only half a diashow.
  #
  # 16:9 as the default: it is the only ratio that fits an unknown mix of club photos
  # without turning a landscape shot into a stamp. Autoplay defaults to off so galleries
  # that exist today do not start moving on deploy.
  def change do
    alter table(:block_image_gallery) do
      add :aspect_ratio, :string, null: false, default: "16:9"
      add :autoplay, :boolean, null: false, default: false
    end

    # `layout` was created defaulting to "slideshow" while `Content.@block_defaults`
    # inserts "grid", so the column default only ever applied to a row written outside
    # `add_block/2` — a data migration, an importer, a hand-written INSERT. Harmless
    # while nothing read `layout`; from now on it would silently make such a row a
    # slideshow. Aligned on the value the application actually means.
    execute "ALTER TABLE block_image_gallery ALTER COLUMN layout SET DEFAULT 'grid'",
            "ALTER TABLE block_image_gallery ALTER COLUMN layout SET DEFAULT 'slideshow'"
  end
end
