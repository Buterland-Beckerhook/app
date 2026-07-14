defmodule Bbh.ContentTest do
  use Bbh.DataCase, async: true

  alias Bbh.Content

  import Bbh.ContentFixtures

  defp days_ago(n), do: DateTime.utc_now() |> DateTime.add(-n, :day) |> DateTime.truncate(:second)

  describe "list_published_articles/2" do
    test "returns only published, real articles, newest first" do
      old = article_fixture(date_published: days_ago(10))
      new = article_fixture(date_published: days_ago(1))
      _draft = article_fixture(status: "draft")
      _throne_only = article_fixture(no_article: true)

      result = Content.list_published_articles()

      ids = Enum.map(result.entries, & &1.id)
      assert ids == [new.id, old.id]
      assert result.total == 2
    end

    test "paginates" do
      for i <- 1..5, do: article_fixture(date_published: days_ago(i))

      page1 = Content.list_published_articles(1, 2)
      page2 = Content.list_published_articles(2, 2)

      assert length(page1.entries) == 2
      assert length(page2.entries) == 2
      assert page1.total == 5
      assert page1.total_pages == 3
      # no overlap between pages
      assert page1.entries
             |> Enum.map(& &1.id)
             |> Enum.all?(&(&1 not in Enum.map(page2.entries, fn e -> e.id end)))
    end
  end

  describe "latest_articles/1" do
    test "returns the n most recent published articles" do
      _old = article_fixture(date_published: days_ago(10))
      mid = article_fixture(date_published: days_ago(5))
      new = article_fixture(date_published: days_ago(1))

      assert [new.id, mid.id] == Content.latest_articles(2) |> Enum.map(& &1.id)
    end
  end

  describe "get_published_article/2" do
    test "returns a published article by slug and year" do
      article = article_fixture(slug: "sommerfest", date_published: days_ago(1))

      found = Content.get_published_article("sommerfest", article.year)
      assert found.id == article.id
    end

    test "does not return unpublished articles" do
      article = article_fixture(slug: "geheim", status: "draft", date_published: days_ago(1))
      refute Content.get_published_article("geheim", article.year)
    end
  end

  describe "current_throne/0 and list_thrones/2" do
    test "current_throne returns the throne with the highest begin year" do
      _older = throne_fixture(begin_year: 2018, end_year: 2019)
      current = throne_fixture(begin_year: 2023, end_year: 2024)

      assert Content.current_throne().id == current.id
    end

    test "list_thrones paginates newest first" do
      _a = throne_fixture(begin_year: 2018, end_year: 2019)
      b = throne_fixture(begin_year: 2023, end_year: 2024)

      result = Content.list_thrones(1, 1)
      assert [only] = result.entries
      assert only.id == b.id
      assert result.total == 2
    end
  end

  describe "get_published_page/1 and load_blocks/1" do
    test "returns the page with its blocks in position order" do
      page = page_fixture(slug: "verein-info")
      {:ok, _} = Content.add_block(page, "richtext")
      {:ok, _} = Content.add_block(page, "alert")

      {loaded_page, blocks} = Content.get_published_page("verein-info")

      assert loaded_page.id == page.id
      assert Enum.map(blocks, fn {pb, _} -> pb.block_type end) == ["richtext", "alert"]
      assert Enum.map(blocks, fn {pb, _} -> pb.position end) == [0, 1]
      # each block tuple carries the resolved concrete struct
      assert Enum.all?(blocks, fn {_pb, block} -> not is_nil(block) end)
    end

    test "returns nil for an unpublished page" do
      page_fixture(slug: "entwurf", status: "draft")
      refute Content.get_published_page("entwurf")
    end
  end

  describe "article images" do
    test "add, list and delete article images" do
      article = article_fixture()
      upload = upload_fixture()

      {:ok, image} = Content.add_article_image(article, upload.id)
      assert image.media_id == upload.id
      assert image.sort == 0

      assert [listed] = Content.list_article_images(article.id)
      assert listed.id == image.id
      assert listed.media.id == upload.id

      {:ok, _} = Content.delete_article_image(image)
      assert Content.list_article_images(article.id) == []
    end

    test "set_article_preview_image/2 is exclusive — only one image is the preview" do
      article = article_fixture()
      {:ok, a} = Content.add_article_image(article, upload_fixture().id)
      {:ok, b} = Content.add_article_image(article, upload_fixture().id)

      assert {:ok, _} = Content.set_article_preview_image(article, a.id)
      assert Content.get_article_image!(a.id).use_as_article_image
      refute Content.get_article_image!(b.id).use_as_article_image

      # Switching to b clears a.
      assert {:ok, _} = Content.set_article_preview_image(article, b.id)
      refute Content.get_article_image!(a.id).use_as_article_image
      assert Content.get_article_image!(b.id).use_as_article_image
    end

    test "set_article_preview_image/2 rejects an image that isn't the article's" do
      article = article_fixture()
      other_image_id = Ecto.UUID.generate()
      assert {:error, :not_found} = Content.set_article_preview_image(article, other_image_id)
    end
  end
end
