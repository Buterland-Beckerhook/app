defmodule Bbh.Content.ArticleImage do
  @moduledoc """
  Join between an article and an uploaded image.

  Carries only the *embedding* decisions. Caption, alt text and copyright belong to
  the media item itself and are edited in the media library (`Bbh.Media.Upload`), so
  the same picture reads the same wherever it is embedded.
  """
  use Bbh.Schema

  schema "article_images" do
    field :logical_name, :string
    field :sort, :integer
    field :show_caption, :boolean, default: true
    field :use_as_throne_picture, :boolean, default: false
    field :use_as_article_image, :boolean, default: false

    belongs_to :article, Bbh.Content.Article
    belongs_to :media, Bbh.Media.Upload

    timestamps()
  end

  @doc false
  def changeset(image, attrs) do
    image
    |> cast(attrs, [
      :logical_name,
      :sort,
      :show_caption,
      :use_as_throne_picture,
      :use_as_article_image,
      :article_id,
      :media_id
    ])
    |> validate_required([:article_id, :media_id])
    |> foreign_key_constraint(:article_id)
    |> foreign_key_constraint(:media_id)
    |> unique_constraint(:use_as_article_image,
      name: :article_images_one_preview,
      message: "es ist bereits ein Vorschaubild gesetzt"
    )
  end
end
