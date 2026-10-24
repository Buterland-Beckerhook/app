defmodule Bbh.Repo.Migrations.AddGridFitToBlockImageGallery do
  use Ecto.Migration

  # How the grid layout frames its pictures: "square" crops (the look every existing
  # gallery has, hence the default) or "original", justified rows in each picture's own
  # aspect ratio. The slideshow ignores it.
  def change do
    alter table(:block_image_gallery) do
      add :grid_fit, :string, null: false, default: "square"
    end
  end
end
