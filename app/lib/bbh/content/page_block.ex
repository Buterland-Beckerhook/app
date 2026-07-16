defmodule Bbh.Content.PageBlock do
  @moduledoc """
  Ordered polymorphic link from a page to a content block. `block_type` names which
  block_* table `block_id` points at (see `Bbh.Content.Blocks`). The concrete block is
  loaded by the context, not via an Ecto association.
  """
  use Bbh.Schema

  schema "page_blocks" do
    field :position, :integer, default: 0
    field :block_type, :string
    field :block_id, :binary_id

    belongs_to :page, Bbh.Content.Page

    timestamps()
  end

  @doc false
  def changeset(page_block, attrs) do
    page_block
    |> cast(attrs, [:position, :block_type, :block_id, :page_id])
    |> validate_required([:position, :block_type, :block_id, :page_id])
    |> validate_inclusion(:block_type, Map.keys(Bbh.Content.Blocks.types()))
    |> foreign_key_constraint(:page_id)
  end
end
