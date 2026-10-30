defmodule Bbh.Media.Folder do
  @moduledoc """
  A folder in the media library. At most `max_depth/0` levels deep, counting the
  top level (`parent_id == nil`) as the first — enough for "Archiv / 2026 /
  Schützenfest", a year with categories inside it.
  """
  use Bbh.Schema

  # The one place the cap is set. Everything else — the context, the LiveView, the tree
  # hook (via `data-max-depth`) — reads it from here.
  @max_depth 3

  schema "media_folders" do
    field :name, :string
    # Hand-ordered within the parent level. Never cast from user params — it is set by
    # Bbh.Media.Folders.create_folder/1 and rewritten wholesale by Bbh.Ordering.renumber/2.
    field :position, :integer, default: 0

    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :uploads, Bbh.Media.Upload

    timestamps()
  end

  @doc "How many levels the tree may have, the top level included."
  def max_depth, do: @max_depth

  @doc """
  The folder's path from the top level down to itself, read off the `parent` chain
  `Bbh.Media.Folders.get_folder/1` preloads. A chain that is not loaded ends the path there.
  """
  def path(%__MODULE__{parent: %__MODULE__{} = parent} = folder), do: path(parent) ++ [folder]
  def path(%__MODULE__{} = folder), do: [folder]

  @doc """
  Changeset for creating or renaming a folder.

  `parent_depth` is the level of the folder it goes into (0 = the top level itself),
  injected by the caller because the schema cannot query.
  """
  def changeset(folder, attrs, parent_depth \\ 0) do
    folder
    |> cast(attrs, [:name, :parent_id])
    |> validate_required([:name])
    |> validate_length(:name, max: 120)
    # Reachable in German-facing UI: two tabs open, one deletes the folder the other is
    # about to drop into. Without a message Ecto's raw "does not exist" reaches the flash.
    |> foreign_key_constraint(:parent_id, message: "Zielordner existiert nicht mehr")
    |> enforce_max_depth(parent_depth + 1)
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

  Creating a folder only ever produces a leaf, so the parent's level is all `changeset/3`
  has to check. A move carries a whole branch along: its deepest folder lands
  `height - 1` levels below the moved one, and the target must not lie inside that
  branch, or the folder would hang from itself and detach from the tree. Both are
  refused here rather than in the caller — the ids come straight from the browser.

  `branch` is `%{ids: [folder id | descendant ids], height: levels}` (a leaf is
  height 1), injected like `parent_depth`.
  """
  def move_changeset(folder, attrs, parent_depth, %{ids: ids, height: height}) do
    folder
    |> changeset(attrs, parent_depth)
    |> enforce_branch_fits(parent_depth, height)
    # Last, because errors are prepended and the flash shows the first: a drop into the
    # folder's own branch usually breaks the cap too, but this is what actually went wrong.
    |> enforce_outside_branch(ids)
  end

  defp enforce_max_depth(changeset, depth) when depth > @max_depth do
    add_error(changeset, :parent_id, "Ordner dürfen nur #{@max_depth} Ebenen tief sein")
  end

  defp enforce_max_depth(changeset, _depth), do: changeset

  # Dropping a folder onto itself or one of its own sub-folders would detach the whole
  # branch from the tree.
  defp enforce_outside_branch(changeset, ids) do
    if get_field(changeset, :parent_id) in ids,
      do: add_error(changeset, :parent_id, "Ordner kann nicht in sich selbst liegen"),
      else: changeset
  end

  # The moved folder itself is covered by enforce_max_depth/2; this is about the
  # sub-folders it brings along.
  defp enforce_branch_fits(changeset, parent_depth, height)
       when height > 1 and parent_depth + height > @max_depth do
    add_error(
      changeset,
      :parent_id,
      "Ordner mit Unterordnern würde tiefer als #{@max_depth} Ebenen liegen"
    )
  end

  defp enforce_branch_fits(changeset, _parent_depth, _height), do: changeset
end
