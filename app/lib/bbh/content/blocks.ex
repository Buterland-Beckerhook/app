defmodule Bbh.Content.Blocks do
  @moduledoc """
  The page content blocks (the Directus M2A block collections). Each block type is
  its own schema/table; `Bbh.Content.PageBlock` orders them on a page polymorphically.

  `block_type` string ↔ block schema mapping used by the renderer and admin editor.
  """

  @types %{
    "richtext" => __MODULE__.RichText,
    "alert" => __MODULE__.Alert,
    "media_card" => __MODULE__.MediaCard,
    "image_gallery" => __MODULE__.ImageGallery,
    "person_list" => __MODULE__.PersonList
  }

  def types, do: @types
  def schema_for(type), do: Map.fetch!(@types, type)
  def type_for(module), do: Enum.find_value(@types, fn {t, m} -> m == module && t end)

  defmodule RichText do
    use Bbh.Schema

    schema "block_richtext" do
      field :body, :string
      timestamps()
    end

    def changeset(block, attrs) do
      block
      |> cast(attrs, [:body])
      |> update_change(:body, &Bbh.Html.sanitize/1)
      |> validate_required([:body])
    end
  end

  defmodule Alert do
    use Bbh.Schema

    @icons ~w(info warning success danger)
    def icons, do: @icons

    schema "block_alert" do
      field :icon, :string, default: "info"
      field :body, :string
      timestamps()
    end

    def changeset(block, attrs) do
      block
      |> cast(attrs, [:icon, :body])
      |> update_change(:body, &Bbh.Html.sanitize/1)
      |> validate_required([:icon, :body])
      |> validate_inclusion(:icon, @icons)
    end
  end

  defmodule MediaCard do
    use Bbh.Schema

    @positions ~w(left right)
    def positions, do: @positions

    schema "block_media_card" do
      field :title, :string
      field :subtitle, :string
      field :body, :string
      field :image_position, :string, default: "right"
      belongs_to :image, Bbh.Media.Upload
      timestamps()
    end

    def changeset(block, attrs) do
      block
      |> cast(attrs, [:title, :subtitle, :body, :image_position, :image_id])
      |> update_change(:body, &Bbh.Html.sanitize/1)
      |> validate_inclusion(:image_position, @positions)
      |> foreign_key_constraint(:image_id)
    end
  end

  defmodule ImageGallery do
    use Bbh.Schema

    @layouts ~w(slideshow grid)
    def layouts, do: @layouts

    schema "block_image_gallery" do
      field :title, :string
      field :layout, :string, default: "slideshow"
      field :lightbox, :boolean, default: true
      has_many :files, Bbh.Content.Blocks.GalleryFile, foreign_key: :gallery_id
      timestamps()
    end

    def changeset(block, attrs) do
      block
      |> cast(attrs, [:title, :layout, :lightbox])
      |> validate_inclusion(:layout, @layouts)
    end
  end

  defmodule GalleryFile do
    use Bbh.Schema

    schema "block_gallery_files" do
      field :title, :string
      field :copyright, :string
      field :sort, :integer
      belongs_to :gallery, Bbh.Content.Blocks.ImageGallery
      belongs_to :media, Bbh.Media.Upload
      timestamps()
    end

    def changeset(file, attrs) do
      file
      |> cast(attrs, [:title, :copyright, :sort, :gallery_id, :media_id])
      |> validate_required([:gallery_id, :media_id])
      |> foreign_key_constraint(:gallery_id)
      |> foreign_key_constraint(:media_id)
    end
  end

  defmodule PersonList do
    use Bbh.Schema

    @honorary ~w(all only exclude)
    @styles ~w(table cards compact)
    def honorary_options, do: @honorary
    def styles, do: @styles

    schema "block_person_list" do
      field :title, :string
      field :filter_roles, {:array, :string}, default: []
      field :filter_honorary, :string, default: "all"
      field :display_style, :string, default: "table"
      field :show_address, :boolean, default: false
      timestamps()
    end

    def changeset(block, attrs) do
      block
      |> cast(attrs, [:title, :filter_roles, :filter_honorary, :display_style, :show_address])
      |> validate_inclusion(:filter_honorary, @honorary)
      |> validate_inclusion(:display_style, @styles)
    end
  end
end
