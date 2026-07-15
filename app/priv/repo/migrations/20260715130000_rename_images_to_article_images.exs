defmodule Bbh.Repo.Migrations.RenameImagesToArticleImages do
  use Ecto.Migration

  # The `images` table is really the article↔media join (see Bbh.Content.ArticleImage).
  # Rename it to match its purpose. Indexes/constraints keep their old names in
  # Postgres after a table rename, so rename the ones we reference explicitly too.
  def up do
    rename table(:images), to: table(:article_images)

    execute "ALTER INDEX IF EXISTS images_article_id_index RENAME TO article_images_article_id_index"
    execute "ALTER INDEX IF EXISTS images_media_id_index RENAME TO article_images_media_id_index"

    # Ensure the media_id index exists (some environments were missing it).
    create_if_not_exists index(:article_images, [:media_id])
  end

  def down do
    execute "ALTER INDEX IF EXISTS article_images_article_id_index RENAME TO images_article_id_index"
    execute "ALTER INDEX IF EXISTS article_images_media_id_index RENAME TO images_media_id_index"

    rename table(:article_images), to: table(:images)
  end
end
