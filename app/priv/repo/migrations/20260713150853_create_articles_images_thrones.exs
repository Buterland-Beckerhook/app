defmodule Bbh.Repo.Migrations.CreateArticlesImagesThrones do
  use Ecto.Migration

  def change do
    create table(:articles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :status, :string, null: false, default: "draft"
      add :title, :string, null: false
      add :subtitle, :string
      add :slug, :string, null: false
      add :date_published, :utc_datetime, null: false
      add :date_modified, :utc_datetime
      # Derived from date_published in the changeset (was a DB trigger in Directus).
      add :year, :integer, null: false
      add :author, :string
      add :tags, {:array, :string}, null: false, default: []
      add :body, :text
      # "Nur Thron-Anzeige, kein eigener Artikel"
      add :no_article, :boolean, null: false, default: false
      # Old Hugo URLs for redirects.
      add :aliases, {:array, :string}, null: false, default: []

      timestamps(type: :utc_datetime)
    end

    create unique_index(:articles, [:slug, :year], name: :articles_slug_year_unique)
    create index(:articles, [:status, :date_published])
    create index(:articles, [:status, :slug, :year])
    create constraint(:articles, :articles_year_range, check: "year >= 1900")

    # Per-article images (join to media, ordered, with hero/throne flags).
    create table(:images, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :article_id, references(:articles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :media_id, references(:media, type: :binary_id, on_delete: :delete_all), null: false
      add :logical_name, :string
      add :title, :string
      add :description, :string
      add :copyright, :string, default: "Buterland-Beckerhook e.V."
      add :sort, :integer
      add :use_as_throne_picture, :boolean, null: false, default: false
      add :use_as_article_image, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:images, [:article_id])
    create index(:images, [:media_id])

    # König/Kaiser records; one per article (has_one).
    create table(:thrones, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :article_id, references(:articles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :type, :string, null: false
      add :begin, :integer, null: false
      add :end, :integer
      add :king_title, :string
      add :king, :string, null: false
      add :queen, :string, null: false
      add :moh1, :string
      add :moh2, :string
      add :loh1, :string
      add :loh2, :string
      add :cupbearer, :string
      add :courtmarshal, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:thrones, [:article_id])
    create index(:thrones, [:type, :begin])

    create constraint(:thrones, :thrones_end_after_begin,
             check: ~s{"end" IS NULL OR "end" >= "begin"}
           )

    create constraint(:thrones, :thrones_begin_positive, check: ~s{"begin" > 0})
  end
end
