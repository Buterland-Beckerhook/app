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

    test "deletes an article", %{conn: conn} do
      article = article_fixture()
      {:ok, lv, _html} = live(conn, ~p"/admin/artikel")

      render_click(lv, "delete", %{"id" => article.id})

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
end
