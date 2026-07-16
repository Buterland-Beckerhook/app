defmodule Bbh.Repo.Migrations.EnforceSingleArticlePreview do
  use Ecto.Migration

  # Only one image per article may be the article/preview image (use_as_article_image).
  # First clear any stray extra flags (keep the earliest inserted per article), then
  # enforce it with a partial unique index.
  def up do
    execute """
    UPDATE article_images ai
    SET use_as_article_image = false
    WHERE use_as_article_image
      AND ai.id <> (
        SELECT keep.id FROM article_images keep
        WHERE keep.article_id = ai.article_id AND keep.use_as_article_image
        ORDER BY keep.inserted_at ASC, keep.id ASC
        LIMIT 1
      )
    """

    create unique_index(:article_images, [:article_id],
             where: "use_as_article_image",
             name: :article_images_one_preview
           )
  end

  def down do
    drop index(:article_images, [:article_id], name: :article_images_one_preview)
  end
end
