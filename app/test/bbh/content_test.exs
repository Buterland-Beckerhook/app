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

    test "include_unpublished: true also lists drafts and scheduled, but not throne-only" do
      published = article_fixture(date_published: days_ago(1))
      draft = article_fixture(status: "draft")
      scheduled = article_fixture(status: "published", date_published: from_now(2))
      _throne_only = article_fixture(no_article: true)

      ids = Content.list_published_articles(1, 10, include_unpublished: true).entries |> Enum.map(& &1.id)

      assert published.id in ids
      assert draft.id in ids
      assert scheduled.id in ids
      assert length(ids) == 3
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

  describe "scheduled pre-publishing" do
    defp from_now(n), do: Bbh.Time.now() |> DateTime.add(n, :day) |> DateTime.truncate(:second)

    test "a published article with a future date stays hidden until then" do
      future =
        article_fixture(slug: "kommt-bald", status: "published", date_published: from_now(2))

      past = article_fixture(slug: "schon-da", status: "published", date_published: from_now(-2))

      ids = Content.list_published_articles().entries |> Enum.map(& &1.id)
      assert past.id in ids
      refute future.id in ids

      assert Enum.map(Content.latest_articles(10), & &1.id) == [past.id]

      assert Content.get_published_article("schon-da", past.year).id == past.id
      refute Content.get_published_article("kommt-bald", future.year)
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

      result = Content.list_thrones("koenig", 1, 1)
      assert [only] = result.entries
      assert only.id == b.id
      assert result.total == 2
    end

    test "current_thrones includes the current Jungschützenkönig" do
      koenig = throne_fixture(type: "koenig", begin_year: 2025, end_year: 2026)

      jsk =
        throne_fixture(
          type: "jungschuetzenkoenig",
          begin_year: 2025,
          end_year: nil,
          king: "Tim Junior",
          queen: nil
        )

      types = Content.current_thrones() |> Enum.map(& &1.type)
      assert "jungschuetzenkoenig" in types
      # König first, Jungschützenkönig last (Kaiser/Stadtkaiser absent here).
      assert types == ["koenig", "jungschuetzenkoenig"]
      assert koenig.type == "koenig" and jsk.type == "jungschuetzenkoenig"
    end

    test "list_thrones preloads the throne picture's media" do
      article = article_fixture(no_article: true, title: "Thron-Eintrag")
      media = upload_fixture()

      %Bbh.Content.ArticleImage{}
      |> Bbh.Content.ArticleImage.changeset(%{
        article_id: article.id,
        media_id: media.id,
        use_as_throne_picture: true
      })
      |> Repo.insert!()

      throne_fixture(article: article, begin_year: 2023, end_year: 2024)

      assert [entry] = Content.list_thrones("koenig", 1, 1).entries
      assert [image] = entry.article.images
      assert image.media.id == media.id
    end

    test "list_throne_nav returns thrones of a type newest first with year/king" do
      _older = throne_fixture(begin_year: 2018, end_year: 2019, king: "Gerd Lübbers")
      _newer = throne_fixture(begin_year: 2023, end_year: 2024, king: "Jan-Bernd Droste")
      # A different type must not leak into the König pager.
      _stadt = throne_fixture(type: "stadtkaiser", begin_year: 2020, king: "Anton Stadt")

      assert [
               %{begin_year: 2023, king: "Jan-Bernd Droste"},
               %{begin_year: 2018, king: "Gerd Lübbers"}
             ] = Content.list_throne_nav("koenig")
    end

    test "list_thrones and list_throne_nav filter by type" do
      koenig = throne_fixture(type: "koenig", begin_year: 2023, end_year: 2024)
      stadt = throne_fixture(type: "stadtkaiser", begin_year: 2020, king: "Anton Stadt")

      assert [%{id: stadt_id}] = Content.list_thrones("stadtkaiser", 1, 1).entries
      assert stadt_id == stadt.id
      assert [%{begin_year: 2020}] = Content.list_throne_nav("stadtkaiser")

      assert [%{id: koenig_id}] = Content.list_thrones("koenig", 1, 1).entries
      assert koenig_id == koenig.id
    end

    test "throne_menu lists Kaiser reigns and the set of present types" do
      _koenig = throne_fixture(type: "koenig", begin_year: 2023, end_year: 2024)

      _kaiser =
        throne_fixture(type: "kaiser", begin_year: 2009, end_year: 2034, king: "Kaiser Karl")

      %{kaiser: kaiser, types_present: types} = Content.throne_menu()

      assert [%{begin_year: 2009, type: "kaiser"}] = kaiser
      assert MapSet.member?(types, "koenig")
      assert MapSet.member?(types, "kaiser")
      refute MapSet.member?(types, "stadtkaiser")
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

  describe "page navigation tree" do
    test "list_menu_pages/0 returns published top-level menu pages, ordered" do
      page_fixture(slug: "b-seite", title: "B", status: "published", sort_order: 2)
      page_fixture(slug: "a-seite", title: "A", status: "published", sort_order: 1)
      # excluded: a child, a draft, and a legal (show_in_menu false) page
      root = page_fixture(slug: "root", status: "published", sort_order: 3)
      page_fixture(slug: "kind", status: "published", parent_id: root.id)
      page_fixture(slug: "entwurf", status: "draft")
      page_fixture(slug: "impressum", status: "published", show_in_menu: false)

      slugs = Content.list_menu_pages() |> Enum.map(& &1.slug)
      assert slugs == ["a-seite", "b-seite", "root"]
    end

    test "get_page_by_path/1 resolves a valid nested path" do
      parent = page_fixture(slug: "ueber-uns", status: "published")
      child = page_fixture(slug: "geschichte", status: "published", parent_id: parent.id)

      assert {resolved, [ancestor, ^child]} =
               Content.get_page_by_path(["ueber-uns", "geschichte"])

      assert resolved.id == child.id
      assert ancestor.id == parent.id
    end

    test "get_page_by_path/1 rejects a wrong ancestor chain" do
      parent = page_fixture(slug: "ueber-uns", status: "published")
      page_fixture(slug: "geschichte", status: "published", parent_id: parent.id)

      # Correct slug but missing/incorrect parent segment.
      refute Content.get_page_by_path(["geschichte"])
      refute Content.get_page_by_path(["falsch", "geschichte"])
    end

    test "get_page_by_path/1 rejects a tree rooted at a non-menu (legal) page" do
      legal = page_fixture(slug: "impressum", status: "published", show_in_menu: false)
      page_fixture(slug: "unterpunkt", status: "published", parent_id: legal.id)

      refute Content.get_page_by_path(["impressum", "unterpunkt"])
    end

    test "section_links/1 flattens the section root-first with depth" do
      root = page_fixture(slug: "ueber-uns", title: "Über uns", status: "published")

      child =
        page_fixture(
          slug: "geschichte",
          title: "Geschichte",
          status: "published",
          parent_id: root.id
        )

      page_fixture(slug: "detail", title: "Detail", status: "published", parent_id: child.id)

      assert [
               %{path: "/verein/ueber-uns", title: "Über uns", depth: 0},
               %{path: "/verein/ueber-uns/geschichte", title: "Geschichte", depth: 1},
               %{path: "/verein/ueber-uns/geschichte/detail", title: "Detail", depth: 2}
             ] = Content.section_links(root)
    end

    test "include_unpublished: true surfaces draft pages for editor preview" do
      published = page_fixture(slug: "sichtbar", status: "published", sort_order: 1)
      draft = page_fixture(slug: "entwurf", status: "draft", sort_order: 2)
      child = page_fixture(slug: "kind", status: "draft", parent_id: published.id)

      # Default (public) view excludes drafts.
      assert Content.list_menu_pages() |> Enum.map(& &1.slug) == ["sichtbar"]
      refute Content.get_page_by_path(["entwurf"])
      refute Content.get_page_by_path(["sichtbar", "kind"])

      # Editor preview includes them.
      preview_slugs = Content.list_menu_pages(true) |> Enum.map(& &1.slug)
      assert "entwurf" in preview_slugs
      assert {%{id: id}, _} = Content.get_page_by_path(["entwurf"], true)
      assert id == draft.id
      assert {%{id: cid}, _} = Content.get_page_by_path(["sichtbar", "kind"], true)
      assert cid == child.id
    end

    test "menu_tree/1 tags each entry with its publish status" do
      page_fixture(slug: "live", status: "published", sort_order: 1)
      page_fixture(slug: "draft", status: "draft", sort_order: 2)

      by_slug =
        Content.menu_tree(true)
        |> Map.new(&{Path.basename(&1.path), &1.status})

      assert by_slug["live"] == "published"
      assert by_slug["draft"] == "draft"
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

    test "images come back in sort order, not insert order" do
      article = article_fixture()
      {:ok, third} = Content.add_article_image(article, upload_fixture().id)
      {:ok, first} = Content.add_article_image(article, upload_fixture().id)
      {:ok, second} = Content.add_article_image(article, upload_fixture().id)

      # Sort deliberately against the insert order.
      {:ok, _} = Content.update_article_image(third, %{sort: 2})
      {:ok, _} = Content.update_article_image(first, %{sort: 0})
      {:ok, _} = Content.update_article_image(second, %{sort: 1})

      expected = [first.id, second.id, third.id]

      # The admin listing …
      assert Enum.map(Content.list_article_images(article.id), & &1.id) == expected

      # … and every preload (article page, homepage, /thron) via preload_order.
      assert Enum.map(Content.get_article!(article.id).images, & &1.id) == expected

      published = Content.get_published_article(article.slug, article.year)
      assert Enum.map(published.images, & &1.id) == expected
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

    test "a second preview image is rejected at the database level" do
      article = article_fixture()
      {:ok, a} = Content.add_article_image(article, upload_fixture().id)
      {:ok, b} = Content.add_article_image(article, upload_fixture().id)

      assert {:ok, _} = Content.set_article_preview_image(article, a.id)

      # Flipping the flag directly (bypassing the exclusive setter) must fail.
      assert {:error, changeset} = Content.update_article_image(b, %{use_as_article_image: true})
      assert %{use_as_article_image: [_]} = errors_on(changeset)
    end
  end

  # Both gallery describes want the same empty block on an empty page.
  defp gallery_block(_ctx) do
    page = page_fixture()
    {:ok, _} = Content.add_block(page, "image_gallery")
    [{pb, gallery}] = Content.load_blocks(Content.get_page!(page.id))
    %{page: page, pb: pb, gallery: gallery}
  end

  describe "image_gallery block settings" do
    setup :gallery_block

    test "a new gallery starts as a grid with the default slideshow settings", %{
      gallery: gallery
    } do
      assert gallery.layout == "grid"
      assert gallery.aspect_ratio == "16:9"
      assert gallery.autoplay == false
    end

    test "the slideshow settings are editable", %{pb: pb} do
      assert {:ok, gallery} =
               Content.update_block(pb, %{
                 "layout" => "slideshow",
                 "aspect_ratio" => "3:4",
                 "autoplay" => "true"
               })

      assert gallery.layout == "slideshow"
      assert gallery.aspect_ratio == "3:4"
      assert gallery.autoplay == true
    end

    test "portrait and landscape ratios are both offered" do
      ratios = Bbh.Content.Blocks.ImageGallery.aspect_ratios()

      # The editor's dropdown reads from here, and the renderer turns each entry into a
      # CSS `aspect-ratio`, so an unparseable entry would silently break the crop.
      assert "16:9" in ratios
      assert "3:4" in ratios
      assert Enum.all?(ratios, &Regex.match?(~r|^\d+:\d+$|, &1))
    end

    test "an unknown aspect ratio is rejected", %{pb: pb} do
      assert {:error, changeset} = Content.update_block(pb, %{"aspect_ratio" => "42:1"})
      assert %{aspect_ratio: [_]} = errors_on(changeset)
    end

    test "a nil layout or ratio is refused by the changeset, not by the database", %{pb: pb} do
      # `validate_inclusion/3` skips nil and both columns are NOT NULL, so without an
      # explicit `validate_required` this came back as a raised Postgrex.Error.
      assert {:error, changeset} = Content.update_block(pb, %{"aspect_ratio" => nil})
      assert %{aspect_ratio: [_]} = errors_on(changeset)

      assert {:error, changeset} = Content.update_block(pb, %{"layout" => nil})
      assert %{layout: [_]} = errors_on(changeset)
    end
  end

  describe "gallery file ordering" do
    setup :gallery_block

    test "adds images in order and lists them with their media", %{gallery: gallery} do
      first = upload_fixture(filename: "a.webp")
      second = upload_fixture(filename: "b.webp")

      {:ok, added_first} = Content.add_gallery_file(gallery, first.id)
      {:ok, added_second} = Content.add_gallery_file(gallery, second.id)

      assert added_first.sort == 0
      assert added_second.sort == 1

      assert [a, b] = Content.list_gallery_files(gallery.id)
      assert [a.media.filename, b.media.filename] == ["a.webp", "b.webp"]
    end

    test "moving a file swaps it with its neighbour", %{gallery: gallery} do
      {:ok, a} = Content.add_gallery_file(gallery, upload_fixture().id)
      {:ok, b} = Content.add_gallery_file(gallery, upload_fixture().id)
      {:ok, c} = Content.add_gallery_file(gallery, upload_fixture().id)

      assert {:ok, _} = Content.move_gallery_file(gallery.id, c, :up)
      assert ids(gallery) == [a.id, c.id, b.id]

      assert {:ok, _} = Content.move_gallery_file(gallery.id, a, :down)
      assert ids(gallery) == [c.id, a.id, b.id]
    end

    test "moving past the edge is a no-op", %{gallery: gallery} do
      {:ok, a} = Content.add_gallery_file(gallery, upload_fixture().id)
      {:ok, b} = Content.add_gallery_file(gallery, upload_fixture().id)

      assert {:ok, :noop} = Content.move_gallery_file(gallery.id, a, :up)
      assert {:ok, :noop} = Content.move_gallery_file(gallery.id, b, :down)
      assert ids(gallery) == [a.id, b.id]
    end

    test "a legacy row without a sort still moves the way the editor clicked", ctx do
      {:ok, a} = Content.add_gallery_file(ctx.gallery, upload_fixture().id)
      {:ok, b} = Content.add_gallery_file(ctx.gallery, upload_fixture().id)

      # `sort` is nullable and predates add_gallery_file/2, so legacy rows can be NULL —
      # and a gap in the sort values is enough to make a naive value swap a no-op.
      Repo.update_all(from(f in Bbh.Content.Blocks.GalleryFile, where: f.id == ^a.id),
        set: [sort: 5]
      )

      Repo.update_all(from(f in Bbh.Content.Blocks.GalleryFile, where: f.id == ^b.id),
        set: [sort: nil]
      )

      # NULLs sort last, so b is at the end.
      assert ids(ctx.gallery) == [a.id, b.id]

      assert {:ok, _} =
               Content.move_gallery_file(ctx.gallery.id, Content.get_gallery_file!(b.id), :up)

      assert ids(ctx.gallery) == [b.id, a.id]
    end

    test "sort values that do not start at zero are renumbered instead of colliding", ctx do
      {:ok, a} = Content.add_gallery_file(ctx.gallery, upload_fixture().id)
      {:ok, b} = Content.add_gallery_file(ctx.gallery, upload_fixture().id)
      {:ok, c} = Content.add_gallery_file(ctx.gallery, upload_fixture().id)

      # What deleting the first image leaves behind: an offset run of sort values.
      for {file, sort} <- [{a, 1}, {b, 2}, {c, 3}] do
        Repo.update_all(from(f in Bbh.Content.Blocks.GalleryFile, where: f.id == ^file.id),
          set: [sort: sort]
        )
      end

      assert {:ok, _} =
               Content.move_gallery_file(ctx.gallery.id, Content.get_gallery_file!(c.id), :up)

      assert ids(ctx.gallery) == [a.id, c.id, b.id]
      # Renumbered densely from zero, so no two rows share a position.
      assert ctx.gallery.id |> Content.list_gallery_files() |> Enum.map(& &1.sort) == [0, 1, 2]
    end

    test "moving a file that is not in this gallery is refused, not a crash", ctx do
      other_page = page_fixture()
      {:ok, _} = Content.add_block(other_page, "image_gallery")
      [{_pb, other_gallery}] = Content.load_blocks(Content.get_page!(other_page.id))
      {:ok, stranger} = Content.add_gallery_file(other_gallery, upload_fixture().id)

      assert {:error, :not_found} = Content.move_gallery_file(ctx.gallery.id, stranger, :up)
    end

    test "removing a file leaves the rest in order", %{gallery: gallery} do
      {:ok, a} = Content.add_gallery_file(gallery, upload_fixture().id)
      {:ok, b} = Content.add_gallery_file(gallery, upload_fixture().id)

      assert {:ok, _} = Content.delete_gallery_file(a)
      assert ids(gallery) == [b.id]
    end

    test "the block preload returns files in sort order", %{page: page, gallery: gallery} do
      {:ok, second} = Content.add_gallery_file(gallery, upload_fixture(filename: "b.webp").id)
      {:ok, first} = Content.add_gallery_file(gallery, upload_fixture(filename: "a.webp").id)
      {:ok, _} = Content.move_gallery_file(gallery.id, first, :up)

      [{_pb, loaded}] = Content.load_blocks(Content.get_page!(page.id))
      assert Enum.map(loaded.files, & &1.id) == [first.id, second.id]
      # media is preloaded for the renderer (caption/copyright/alt come from it)
      assert Enum.all?(loaded.files, &match?(%Bbh.Media.Upload{}, &1.media))
    end

    defp ids(gallery), do: gallery.id |> Content.list_gallery_files() |> Enum.map(& &1.id)
  end

  describe "article date fields" do
    test "editing bumps date_modified but leaves date_published untouched" do
      published = days_ago(30)
      article = article_fixture(date_published: published)
      assert is_nil(article.date_modified)

      {:ok, updated} = Content.update_article(article, %{title: "Neuer Titel"})

      assert updated.date_published == published
      assert %DateTime{} = updated.date_modified
    end

    test "date_modified stays nil on create and when nothing changes" do
      article = article_fixture()
      assert is_nil(article.date_modified)

      {:ok, unchanged} = Content.update_article(article, %{})
      assert is_nil(unchanged.date_modified)
    end
  end
end
