defmodule Bbh.ContentFixtures do
  @moduledoc "Test helpers for creating articles, thrones, pages and media."

  alias Bbh.Content
  alias Bbh.Media.Upload
  alias Bbh.Repo

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
    article
  end

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
