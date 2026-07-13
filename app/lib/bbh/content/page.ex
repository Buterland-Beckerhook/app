defmodule Bbh.Content.Page do
  @moduledoc "Static, block-based page (Impressum, Datenschutz, Verein sub-pages)."
  use Bbh.Schema

  @statuses ~w(draft published)
  def statuses, do: @statuses

  schema "pages" do
    field :status, :string, default: "draft"
    field :title, :string
    field :slug, :string
    field :sort_order, :integer, default: 0

    belongs_to :parent, Bbh.Content.Page
    has_many :page_blocks, Bbh.Content.PageBlock, preload_order: [asc: :position]

    timestamps()
  end

  @doc false
  def changeset(page, attrs) do
    page
    |> cast(attrs, [:status, :title, :slug, :sort_order, :parent_id])
    |> validate_required([:status, :title, :slug])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:slug)
  end
end
