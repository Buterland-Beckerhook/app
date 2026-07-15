defmodule Bbh.Media.Folder do
  @moduledoc """
  A folder in the media library. At most two levels deep: a top-level folder
  (`parent_id == nil`) may contain sub-folders, but a sub-folder may not.
  """
  use Bbh.Schema

  schema "media_folders" do
    field :name, :string

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
    |> foreign_key_constraint(:parent_id)
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

  # A sub-folder's parent must itself be top-level (parent_id == nil), so the tree
  # can never exceed two levels.
  defp enforce_max_depth(changeset, %__MODULE__{parent_id: pid}) when not is_nil(pid) do
    add_error(changeset, :parent_id, "Ordner dürfen nur zwei Ebenen tief sein")
  end

  defp enforce_max_depth(changeset, _parent), do: changeset
end
