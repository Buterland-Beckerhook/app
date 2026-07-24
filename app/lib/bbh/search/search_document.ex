defmodule Bbh.Search.SearchDocument do
  @moduledoc """
  A single entry in the unified full-text search index (`search_documents`).

  Rows are built and refreshed by `Bbh.Search.reindex_all/0` from published
  content across the contexts. `search_vector` is a Postgres-generated column
  (see the migration) and is queried only through SQL fragments, so it is not
  mapped as a field here. `headline` is a virtual assign populated by the search
  query (a `ts_headline` snippet with `<mark>` around the matched terms).
  """
  use Bbh.Schema

  @source_types ~w(article event page)
  def source_types, do: @source_types

  schema "search_documents" do
    field :source_type, :string
    field :source_id, :binary_id
    field :title, :string
    field :url, :string
    field :content, :string
    field :document_date, :utc_datetime

    field :headline, :string, virtual: true

    timestamps(type: :utc_datetime)
  end
end
