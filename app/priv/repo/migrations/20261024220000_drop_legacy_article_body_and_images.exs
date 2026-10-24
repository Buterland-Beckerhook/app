defmodule Bbh.Repo.Migrations.DropLegacyArticleBodyAndImages do
  use Ecto.Migration

  # Since the article page-blocks migration (20260727130000) an article's text lives in a
  # richtext block, its images in gallery blocks and its hero in `articles.image_id`.
  # `articles.body` and `article_images` were kept one release for rollback and are no
  # longer read. `down` restores the empty structure only — the data comes from a backup.
  def up do
    drop table(:article_images)

    alter table(:articles) do
      remove :body
    end
  end

  def down do
    alter table(:articles) do
      add :body, :text
    end

    create table(:article_images, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :article_id, references(:articles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :media_id, references(:media, type: :binary_id, on_delete: :delete_all), null: false
      add :logical_name, :string
      add :sort, :integer
      add :show_caption, :boolean, null: false, default: true
      add :use_as_throne_picture, :boolean, null: false, default: false
      add :use_as_article_image, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:article_images, [:article_id])
    create index(:article_images, [:media_id])

    create unique_index(:article_images, [:article_id],
             where: "use_as_article_image",
             name: :article_images_one_preview
           )
  end
end
