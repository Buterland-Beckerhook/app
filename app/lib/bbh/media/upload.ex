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
    field :description, :string
    field :copyright, :string

    belongs_to :folder, Bbh.Media.Folder

    timestamps()
  end

  # Derived server-side at upload time (magic-byte sniffing, dimensions, the
  # generated storage key) — never settable from client params after creation.
  @system_fields [:storage_key, :filename, :content_type, :byte_size, :width, :height]
  # User-editable metadata, safe to cast from admin form params.
  @user_fields [:focal_point_x, :focal_point_y, :title, :description, :copyright, :folder_id]

  # storage_key is a relative path under uploads_dir (e.g. "<year>/<uuid><ext>",
  # see Bbh.Media.do_store_file/3). Each segment must start with an alphanumeric,
  # which forbids "..", leading "/", and empty segments — so path-derived
  # operations (File.rm/cp!/send_file) can never escape uploads_dir.
  @storage_key_format ~r{\A[A-Za-z0-9][A-Za-z0-9._-]*(?:/[A-Za-z0-9][A-Za-z0-9._-]*)*\z}

  @doc "Changeset for creating an upload (sets the server-derived system fields)."
  def changeset(upload, attrs) do
    upload
    |> cast(attrs, @system_fields ++ @user_fields)
    |> validate_required([:storage_key, :filename])
    |> validate_format(:storage_key, @storage_key_format)
    |> foreign_key_constraint(:folder_id)
    |> unique_constraint(:storage_key)
  end

  @doc """
  Changeset for the admin edit form — only user-editable metadata. System fields
  (storage_key, content_type, byte_size, dimensions) are intentionally excluded so
  they cannot be overwritten via crafted form params.
  """
  def update_changeset(upload, attrs) do
    upload
    |> cast(attrs, @user_fields)
    |> foreign_key_constraint(:folder_id)
  end
end
