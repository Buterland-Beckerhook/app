defmodule Bbh.ContentFixtures do
  @moduledoc "Test helpers for creating articles, thrones, pages and media."

  alias Bbh.Content
  alias Bbh.Content.Blocks
  alias Bbh.Media.Upload
  alias Bbh.Repo

  @doc """
  Create an article. Its `body` (unless blank) is stored as a richtext content block,
  the article body's new home — so the article renders and is searchable like a real one.
  """
  def article_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        status: "published",
        title: "Ein Artikel",
        slug: "artikel-#{System.unique_integer([:positive])}",
        date_published: DateTime.utc_now() |> DateTime.truncate(:second),
        body: "<p>Inhalt</p>"
      })

    {:ok, article} = Content.create_article(attrs)

    case attrs[:body] do
      body when is_binary(body) and body not in ["", "<p></p>"] ->
        richtext_block_fixture(article, body)

      _ ->
        :ok
    end

    article
  end

  @doc "Attach a richtext content block carrying `body` to an owner (page or article)."
  def richtext_block_fixture(owner, body \\ "<p>Inhalt</p>") do
    {:ok, _} = Content.add_block(owner, "richtext")
    {pb, _} = owner |> Content.load_blocks() |> List.last()
    {:ok, block} = Content.update_block(pb, %{"body" => body})
    block
  end

  @doc "Attach a grid image-gallery block with `uploads` (in order) to an owner."
  def gallery_block_fixture(owner, uploads) do
    {:ok, _} = Content.add_block(owner, "image_gallery")
    {_pb, gallery} = owner |> Content.load_blocks() |> List.last()
    Enum.each(uploads, fn u -> {:ok, _} = Content.add_gallery_file(gallery, upload_id(u)) end)
    Blocks.ImageGallery |> Repo.get!(gallery.id) |> Repo.preload(files: :media)
  end

  @doc "Set an article's single image (accepts an `%Upload{}` or a media id)."
  def set_article_image(article, upload) do
    {:ok, article} = Content.set_article_image(article, upload_id(upload))
    article
  end

  defp upload_id(%Upload{id: id}), do: id
  defp upload_id(id) when is_binary(id), do: id

  def throne_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)

    article =
      Map.get_lazy(attrs, :article, fn ->
        article_fixture(%{no_article: true, title: "Thron-Eintrag"})
      end)

    attrs =
      attrs
      |> Map.delete(:article)
      |> Enum.into(%{
        type: "koenig",
        begin_year: 2020,
        end_year: 2021,
        king: "Max Mustermann",
        queen: "Erika Mustermann",
        article_id: article.id
      })

    {:ok, throne} = Content.create_throne(attrs)
    throne
  end

  def page_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        status: "published",
        title: "Eine Seite",
        slug: "seite-#{System.unique_integer([:positive])}"
      })

    {:ok, page} = Content.create_page(attrs)
    page
  end

  def upload_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        storage_key: "media/#{System.unique_integer([:positive])}.webp",
        filename: "bild.webp",
        content_type: "image/webp"
      })

    %Upload{} |> Upload.changeset(attrs) |> Repo.insert!()
  end
end
