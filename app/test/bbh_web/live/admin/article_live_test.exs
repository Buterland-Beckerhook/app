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

  describe "article image (edit)" do
    test "shows the picker and current image, and can clear it", ctx do
      article = article_fixture()
      set_article_image(article, upload_fixture(%{caption: "Der Thron 2025"}))

      {:ok, lv, html} = live(ctx.conn, ~p"/admin/artikel/#{article.id}/bearbeiten")

      # The media picker button is wired for the single article image …
      assert has_element?(lv, ~s(button[phx-value-context="article_image"]))
      assert html =~ "Bild ändern"

      # … and clearing it removes the article image.
      html = lv |> element(~s(button[phx-click="clear_article_image"])) |> render_click()

      assert html =~ "Bild wählen"
      assert is_nil(Content.get_article!(article.id).image_id)
    end
  end

  describe "content blocks (edit)" do
    test "adds a content block to the article", ctx do
      article = article_fixture(body: "")
      assert Content.load_blocks(article) == []

      {:ok, lv, _html} = live(ctx.conn, ~p"/admin/artikel/#{article.id}/bearbeiten")

      html =
        lv
        |> form("form[phx-submit=add_block]", type: "richtext")
        |> render_submit()

      assert html =~ "Block speichern"
      assert [{pb, _}] = Content.load_blocks(Content.get_article!(article.id))
      assert pb.block_type == "richtext"
    end
  end

  describe "throne image (edit)" do
    test "the throne image inherits the article image until its own is set", ctx do
      article = article_fixture()
      set_article_image(article, upload_fixture())
      throne_fixture(%{article: article})

      {:ok, lv, html} = live(ctx.conn, ~p"/admin/artikel/#{article.id}/bearbeiten")

      assert html =~ "Thronbild"
      assert html =~ "Erbt das Artikelbild."
      assert has_element?(lv, ~s(button[phx-value-context="throne_image"]))
    end
  end
end
