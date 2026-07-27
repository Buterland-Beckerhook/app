defmodule Bbh.Content.ArticleBlock do
  @moduledoc """
  Ordered polymorphic link from an article to a content block. `block_type` names which
  block_* table `block_id` points at (see `Bbh.Content.Blocks`). The concrete block is
  loaded by the context, not via an Ecto association.

  The parallel to `Bbh.Content.PageBlock`: both order the same owner-agnostic `block_*`
  tables, one for pages and one for articles.
  """
  use Bbh.Schema

  schema "article_blocks" do
    field :position, :integer, default: 0
    field :block_type, :string
    field :block_id, :binary_id

    belongs_to :article, Bbh.Content.Article

    timestamps()
  end

  @doc false
  def changeset(article_block, attrs) do
    article_block
    |> cast(attrs, [:position, :block_type, :block_id, :article_id])
    |> validate_required([:position, :block_type, :block_id, :article_id])
    |> validate_inclusion(:block_type, Map.keys(Bbh.Content.Blocks.types()))
    |> foreign_key_constraint(:article_id)
  end
end
