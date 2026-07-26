defmodule Bbh.Media.Folder do
  @moduledoc """
  A folder in the media library. At most two levels deep: a top-level folder
  (`parent_id == nil`) may contain sub-folders, but a sub-folder may not.
  """
  use Bbh.Schema

  schema "media_folders" do
    field :name, :string
    # Hand-ordered within the parent level. Never cast from user params — it is set by
    # Bbh.Media.create_folder/1 and rewritten wholesale by Bbh.Ordering.renumber/2.
    field :position, :integer, default: 0

    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :uploads, Bbh.Media.Upload

    timestamps()
  end

  @doc false
  def changeset(folder, attrs, parent \\ nil) do
    folder
    |> cast(attrs, [:name, :parent_id])
    |> validate_required([:name])
    |> validate_length(:name, max: 120)
    # Reachable in German-facing UI: two tabs open, one deletes the folder the other is
    # about to drop into. Without a message Ecto's raw "does not exist" reaches the flash.
    |> foreign_key_constraint(:parent_id, message: "Zielordner existiert nicht mehr")
    |> enforce_max_depth(parent)
    |> unique_constraint([:parent_id, :name],
      name: :media_folders_parent_name_index,
      message: "Ordner mit diesem Namen existiert bereits"
    )
    |> unique_constraint(:name,
      name: :media_folders_root_name_index,
      message: "Ordner mit diesem Namen existiert bereits"
    )
  end

  @doc """
  Changeset for re-hanging an existing folder (drag & drop in the media tree).

  Creating a folder can only ever produce a leaf, so `changeset/3` alone was enough
  while the parent was the only thing that could break the two-level cap. Dragging
  opens two more routes to a third level that could not exist before, and both have
  to be refused here rather than in the caller: the ids come straight from the
  browser.

  `has_children?` is injected the same way `parent` is — the schema cannot query.
  """
  def move_changeset(folder, attrs, parent, has_children?) do
    folder
    |> changeset(attrs, parent)
    |> enforce_not_self_parent(folder)
    |> enforce_leaf_when_nesting(has_children?)
  end

  # A sub-folder's parent must itself be top-level (parent_id == nil), so the tree
  # can never exceed two levels.
  defp enforce_max_depth(changeset, %__MODULE__{parent_id: pid}) when not is_nil(pid) do
    add_error(changeset, :parent_id, "Ordner dürfen nur zwei Ebenen tief sein")
  end

  defp enforce_max_depth(changeset, _parent), do: changeset

  # Dropping a folder onto itself would detach it and its whole subtree from the tree.
  defp enforce_not_self_parent(changeset, %__MODULE__{id: id}) when not is_nil(id) do
    if get_field(changeset, :parent_id) == id,
      do: add_error(changeset, :parent_id, "Ordner kann nicht in sich selbst liegen"),
      else: changeset
  end

  defp enforce_not_self_parent(changeset, _folder), do: changeset

  # A folder that already has sub-folders cannot become one itself — its children
  # would land on a third level.
  defp enforce_leaf_when_nesting(changeset, true) do
    if get_field(changeset, :parent_id),
      do:
        add_error(
          changeset,
          :parent_id,
          "Ordner mit Unterordnern kann nicht verschachtelt werden"
        ),
      else: changeset
  end

  defp enforce_leaf_when_nesting(changeset, _has_children?), do: changeset
end
