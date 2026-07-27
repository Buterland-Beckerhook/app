defmodule Bbh.Media.Upload do
  @moduledoc "An uploaded file (original). Responsive variants are derived from it."
  use Bbh.Schema

  schema "media" do
    field :storage_key, :string
    field :filename, :string
    field :content_type, :string
    field :byte_size, :integer
    field :width, :integer
    field :height, :integer
    field :focal_point_x, :float
    field :focal_point_y, :float
    field :title, :string
    field :caption, :string
    field :description, :string
    field :copyright, :string
    # Incremented whenever the stored original is rewritten (see Bbh.Media.rotate_upload/2).
    field :revision, :integer, default: 0

    belongs_to :folder, Bbh.Media.Folder

    timestamps()
  end

  # Derived server-side at upload time (magic-byte sniffing, dimensions, the
  # generated storage key) — never settable from client params after creation.
  # `revision` is bumped only by Bbh.Media.rotate_upload/2, so it is in neither list.
  @system_fields [:storage_key, :filename, :content_type, :byte_size, :width, :height]
  # User-editable metadata, safe to cast from admin form params.
  @user_fields [
    :focal_point_x,
    :focal_point_y,
    :title,
    :caption,
    :description,
    :copyright,
    :folder_id
  ]

  # storage_key is a relative path under uploads_dir (e.g. "<year>/<uuid><ext>",
  # see Bbh.Media.do_store_file/3). Each segment must start with an alphanumeric,
  # which forbids "..", leading "/", and empty segments — so path-derived
  # operations (File.rm/cp!/send_file) can never escape uploads_dir.
  @storage_key_format ~r{\A[A-Za-z0-9][A-Za-z0-9._-]*(?:/[A-Za-z0-9][A-Za-z0-9._-]*)*\z}

  # Applied only on create so freshly uploaded media carry the club as the default
  # rights holder; admins can still clear or override it later (update_changeset).
  @default_copyright "Buterland-Beckerhook e.V."

  @doc "Changeset for creating an upload (sets the server-derived system fields)."
  def changeset(upload, attrs) do
    upload
    |> cast(attrs, @system_fields ++ @user_fields)
    |> put_default_copyright()
    |> validate_required([:storage_key, :filename])
    |> validate_format(:storage_key, @storage_key_format)
    |> validate_folder_id()
    |> foreign_key_constraint(:folder_id)
    |> unique_constraint(:storage_key)
  end

  defp put_default_copyright(changeset) do
    case get_field(changeset, :copyright) do
      value when value in [nil, ""] -> put_change(changeset, :copyright, @default_copyright)
      _ -> changeset
    end
  end

  @doc """
  Changeset for the admin edit form — only user-editable metadata. System fields
  (storage_key, content_type, byte_size, dimensions) are intentionally excluded so
  they cannot be overwritten via crafted form params.
  """
  def update_changeset(upload, attrs) do
    upload
    |> cast(attrs, @user_fields)
    |> validate_folder_id()
    |> foreign_key_constraint(:folder_id)
  end

  # Ecto casts `:binary_id` without checking the shape, so a malformed id survives the
  # changeset and only blows up in `Repo.update` as an `Ecto.ChangeError` — an exception
  # rather than a changeset error, i.e. a crashed LiveView instead of a flash. This value
  # arrives from a drag & drop payload (`move_media`) and from the editor's form post, so
  # the check belongs here rather than at one of the call sites.
  defp validate_folder_id(changeset) do
    validate_change(changeset, :folder_id, fn :folder_id, value ->
      case Ecto.UUID.cast(value) do
        {:ok, _uuid} -> []
        :error -> [folder_id: "ist kein gültiger Ordner"]
      end
    end)
  end
end
