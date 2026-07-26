defmodule BbhWeb.Admin.ArticleLiveTest do
  use BbhWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Bbh.ContentFixtures

  alias Bbh.Content

  setup :register_and_log_in_admin

  describe "Index" do
    test "lists existing articles", %{conn: conn} do
      article = article_fixture(title: "Sommerfest 2026")
      {:ok, _lv, html} = live(conn, ~p"/admin/artikel")

      assert html =~ "Artikel"
      assert html =~ article.title
    end

    test "filters the list by title", %{conn: conn} do
      article_fixture(title: "Sommerfest 2026")
      article_fixture(title: "Winterball 2026")

      {:ok, lv, _html} = live(conn, ~p"/admin/artikel")

      html =
        lv
        |> form("#list-search", %{q: "winter"})
        |> render_change()

      assert html =~ "Winterball 2026"
      refute html =~ "Sommerfest 2026"
    end

    test "deletes an article from the edit page with slug confirmation", %{conn: conn} do
      article = article_fixture()
      {:ok, lv, _html} = live(conn, ~p"/admin/artikel/#{article.id}/bearbeiten")

      {:ok, _lv, html} =
        lv
        |> form("form[phx-submit=delete]", confirm: article.slug)
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/artikel")

      assert html =~ "Artikel gelöscht"
      assert_raise Ecto.NoResultsError, fn -> Content.get_article!(article.id) end
    end
  end

  describe "Form (new)" do
    test "renders the new form", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/admin/artikel/neu")
      assert html =~ "Neuer Artikel"
      assert html =~ "Titel"
    end

    test "wires slug auto-generation from the title input", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/artikel/neu")
      # The client-side hook (SlugFromTitle) fills the slug from the title; here we
      # only guard that it stays wired to a title input with a slug target present.
      assert has_element?(lv, "#article_title[phx-hook='SlugFromTitle']")
      assert has_element?(lv, "#article_slug")
    end

    test "creates an article and redirects to its edit page", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/artikel/neu")

      {:ok, _lv, html} =
        lv
        |> form("#article-form", article: %{title: "Neuer Bericht", slug: "neuer-bericht"})
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "Artikel erstellt"
      assert html =~ "Artikel bearbeiten"
      assert html =~ "Neuer Bericht"
    end
  end

  describe "Form (edit)" do
    test "saving an edit stays on the edit page", %{conn: conn} do
      article = article_fixture(title: "Alt")
      {:ok, lv, _html} = live(conn, ~p"/admin/artikel/#{article.id}/bearbeiten")

      html =
        lv
        |> form("#article-form", article: %{title: "Neu"})
        |> render_submit()

      assert html =~ "Artikel gespeichert"
      assert html =~ "Artikel bearbeiten"
      assert Content.get_article!(article.id).title == "Neu"
    end

    test "links to the public view for a published article", %{conn: conn} do
      article = article_fixture(status: "published", title: "Live")
      {:ok, _lv, html} = live(conn, ~p"/admin/artikel/#{article.id}/bearbeiten")

      assert html =~ "Ansehen"
      assert html =~ ~p"/aktuell/#{article.year}/#{article.slug}"
    end

    test "labels the view button as preview for a draft", %{conn: conn} do
      article = article_fixture(status: "draft", title: "Entwurf")
      {:ok, _lv, html} = live(conn, ~p"/admin/artikel/#{article.id}/bearbeiten")

      assert html =~ "Vorschau"
    end

    test "editing the title does not reset the published date", %{conn: conn} do
      published = ~U[2025-03-04 09:30:00Z]
      article = article_fixture(date_published: published, title: "Alt")

      {:ok, lv, _html} = live(conn, ~p"/admin/artikel/#{article.id}/bearbeiten")

      # Submit a change that omits date_published from the params entirely.
      lv
      |> form("#article-form", article: %{title: "Neu"})
      |> render_submit()

      updated = Content.get_article!(article.id)
      assert updated.title == "Neu"
      assert updated.date_published == published
    end
  end

  describe "article images (edit)" do
    test "an image carries only embedding options — text lives in the media library", ctx do
      article = article_fixture()
      upload = upload_fixture(%{caption: "Der Thron 2025", copyright: "BBH e.V."})
      {:ok, image} = Content.add_article_image(article, upload.id)

      {:ok, lv, html} = live(ctx.conn, ~p"/admin/artikel/#{article.id}/bearbeiten")

      # The media item's text is shown for orientation …
      assert html =~ "Der Thron 2025"
      assert html =~ "BBH e.V."
      # … but is not editable here.
      refute has_element?(lv, ~s(#image-#{image.id} input[name="image[title]"]))
      refute has_element?(lv, ~s(#image-#{image.id} input[name="image[copyright]"]))
      assert has_element?(lv, ~s(#image-#{image.id} input[name="image[show_caption]"]))
    end

    test "the caption can be switched off for this article only", ctx do
      article = article_fixture()
      upload = upload_fixture(%{caption: "Der Thron 2025"})
      {:ok, image} = Content.add_article_image(article, upload.id)
      assert image.show_caption

      {:ok, lv, _html} = live(ctx.conn, ~p"/admin/artikel/#{article.id}/bearbeiten")

      html =
        lv
        |> form("#image-#{image.id}", image: %{show_caption: false})
        |> render_submit()

      assert html =~ "Bild gespeichert"
      refute Content.get_article_image!(image.id).show_caption
      # The media item itself is untouched.
      assert Bbh.Media.get_upload!(upload.id).caption == "Der Thron 2025"
    end
  end

  describe "media editor (edit)" do
    test "opens the focal-point editor and saves it without leaving the form", %{conn: conn} do
      article = article_fixture()
      upload = upload_fixture()
      {:ok, _} = Content.add_article_image(article, upload.id)

      {:ok, lv, _html} = live(conn, ~p"/admin/artikel/#{article.id}/bearbeiten")

      html =
        lv
        |> element(~s(button[phx-click="edit_media"][phx-value-upload_id="#{upload.id}"]))
        |> render_click()

      assert html =~ "Datei bearbeiten"

      # The focal-point fields are hidden inputs driven by the JS hook, so submit
      # the event directly with the values the hook would have set.
      html =
        render_submit(lv, "save_meta", %{
          "upload" => %{"focal_point_x" => "0.25", "focal_point_y" => "0.75"}
        })

      assert html =~ "Bild gespeichert"
      refute html =~ "Datei bearbeiten"

      updated = Bbh.Media.get_upload!(upload.id)
      assert updated.focal_point_x == 0.25
      assert updated.focal_point_y == 0.75
    end
  end

  describe "preview image (edit)" do
    test "setting a preview image is exclusive", %{conn: conn} do
      article = article_fixture()
      {:ok, a} = Content.add_article_image(article, upload_fixture().id)
      {:ok, b} = Content.add_article_image(article, upload_fixture().id)

      {:ok, lv, _html} = live(conn, ~p"/admin/artikel/#{article.id}/bearbeiten")

      # Click the actual per-image button, not just the raw event.
      html =
        lv
        |> element(~s(button[phx-click="set_preview_image"][phx-value-img_id="#{b.id}"]))
        |> render_click()

      assert html =~ "Vorschaubild festgelegt"
      assert html =~ "★ Vorschaubild"
      assert Content.get_article_image!(b.id).use_as_article_image
      refute Content.get_article_image!(a.id).use_as_article_image
    end
  end
end
