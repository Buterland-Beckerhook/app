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

    timestamps()
  end

  @doc false
  def changeset(upload, attrs) do
    upload
    |> cast(attrs, [
      :storage_key,
      :filename,
      :content_type,
      :byte_size,
      :width,
      :height,
      :focal_point_x,
      :focal_point_y,
      :title,
      :description,
      :copyright
    ])
    |> validate_required([:storage_key, :filename])
    |> unique_constraint(:storage_key)
  end
end
