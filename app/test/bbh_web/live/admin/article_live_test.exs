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
      # Drain the edit page's assign_async (media library) so navigating away on
      # delete doesn't kill an in-flight DB task on the test's sandbox connection.
      render_async(lv)

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

    test "creates an article and redirects to the index", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/artikel/neu")

      {:ok, _lv, html} =
        lv
        |> form("#article-form", article: %{title: "Neuer Bericht", slug: "neuer-bericht"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/artikel")

      assert html =~ "Artikel erstellt"
      assert html =~ "Neuer Bericht"
    end
  end

  describe "Form (edit)" do
    test "editing the title does not reset the published date", %{conn: conn} do
      published = ~U[2025-03-04 09:30:00Z]
      article = article_fixture(date_published: published, title: "Alt")

      {:ok, lv, _html} = live(conn, ~p"/admin/artikel/#{article.id}/bearbeiten")
      render_async(lv)

      # Submit a change that omits date_published from the params entirely.
      lv
      |> form("#article-form", article: %{title: "Neu"})
      |> render_submit()

      updated = Content.get_article!(article.id)
      assert updated.title == "Neu"
      assert updated.date_published == published
    end
  end

  describe "preview image (edit)" do
    test "setting a preview image is exclusive", %{conn: conn} do
      article = article_fixture()
      {:ok, a} = Content.add_article_image(article, upload_fixture().id)
      {:ok, b} = Content.add_article_image(article, upload_fixture().id)

      {:ok, lv, _html} = live(conn, ~p"/admin/artikel/#{article.id}/bearbeiten")
      render_async(lv)

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
