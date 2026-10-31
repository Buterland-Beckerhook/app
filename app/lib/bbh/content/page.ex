defmodule Bbh.Content.Page do
  @moduledoc """
  Static, block-based page.

  Where a page is served is decided by the `placement` of its top-level root:

    * `"menu"`     — part of the "Verein" menu, served under `/verein/*path`.
    * `"unlisted"` — outside the menu, served under `/seite/:slug`; reachable only
      through links (e.g. from an event or article). Top-level only, no children.
    * `"system"`   — embedded by the application itself (Impressum, Datenschutz,
      membership-form snippets) and never served on a generic route.

  Child pages always carry `"menu"`: they inherit the menu tree of their root.

  `noindex` keeps a page out of search engines (`X-Robots-Tag`), the sitemap and
  the on-site search.
  """
  use Bbh.Schema

  @statuses ~w(draft published)
  def statuses, do: @statuses

  @placements ~w(menu unlisted system)
  def placements, do: @placements

  schema "pages" do
    field :status, :string, default: "draft"
    field :title, :string
    field :slug, :string
    field :sort_order, :integer, default: 0
    field :placement, :string, default: "menu"
    field :noindex, :boolean, default: false

    # Set by Content.Pages.list_pages_tree/0 for indented tree rendering; not persisted.
    field :depth, :integer, virtual: true

    belongs_to :parent, Bbh.Content.Page
    has_many :children, Bbh.Content.Page, foreign_key: :parent_id
    has_many :page_blocks, Bbh.Content.PageBlock, preload_order: [asc: :position]

    timestamps()
  end

  @doc false
  def changeset(page, attrs) do
    page
    |> cast(attrs, [:status, :title, :slug, :sort_order, :placement, :noindex, :parent_id])
    |> validate_required([:status, :title, :slug, :placement])
    |> Bbh.Slug.validate()
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:placement, @placements)
    |> validate_not_self_parent()
    |> validate_child_placement()
    |> unique_constraint(:slug)
    |> foreign_key_constraint(:parent_id)
  end

  # Placement is a property of the top-level page; a child lives in its root's
  # menu tree. An unlisted or system page cannot be nested.
  defp validate_child_placement(changeset) do
    if get_field(changeset, :parent_id) && get_field(changeset, :placement) != "menu" do
      add_error(
        changeset,
        :placement,
        "Unterseiten erscheinen immer im Menü ihrer Elternseite. Nur Top-Level-Seiten können „Nur per Link“ oder „Sonderseite“ sein."
      )
    else
      changeset
    end
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
