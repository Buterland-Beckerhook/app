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
