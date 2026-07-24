defmodule Bbh.Repo.Migrations.CreateSearchDocuments do
  use Ecto.Migration

  # Unified full-text search index. One row per public document (article, event,
  # page); rebuilt wholesale by Bbh.Workers.SearchReindexer. `search_vector` is a
  # generated column so Postgres keeps it in sync with title/content, weighted
  # title = A, content = B, using the built-in German text-search config.
  def up do
    create table(:search_documents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :source_type, :string, null: false
      add :source_id, :binary_id, null: false
      add :title, :string, null: false
      add :url, :string, null: false
      add :content, :text
      add :document_date, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    execute """
    ALTER TABLE search_documents ADD COLUMN search_vector tsvector
      GENERATED ALWAYS AS (
        setweight(to_tsvector('german', coalesce(title, '')), 'A') ||
        setweight(to_tsvector('german', coalesce(content, '')), 'B')
      ) STORED
    """

    execute "CREATE INDEX search_documents_vector_idx ON search_documents USING GIN (search_vector)"

    create unique_index(:search_documents, [:source_type, :source_id])
  end

  def down do
    drop table(:search_documents)
  end
end
