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
    field :show_in_menu, :boolean, default: true

    belongs_to :parent, Bbh.Content.Page
    has_many :children, Bbh.Content.Page, foreign_key: :parent_id
    has_many :page_blocks, Bbh.Content.PageBlock, preload_order: [asc: :position]

    timestamps()
  end

  @doc false
  def changeset(page, attrs) do
    page
    |> cast(attrs, [:status, :title, :slug, :sort_order, :show_in_menu, :parent_id])
    |> validate_required([:status, :title, :slug])
    |> validate_inclusion(:status, @statuses)
    |> validate_not_self_parent()
    |> unique_constraint(:slug)
    |> foreign_key_constraint(:parent_id)
  end

  # A page cannot be its own parent. Deeper cycles are prevented in the admin UI,
  # which hides the page itself and its descendants from the parent picker.
  defp validate_not_self_parent(changeset) do
    id = get_field(changeset, :id)

    case get_change(changeset, :parent_id) do
      ^id when not is_nil(id) ->
        add_error(changeset, :parent_id, "Eine Seite kann nicht ihre eigene Elternseite sein.")

      _ ->
        changeset
    end
  end
end
