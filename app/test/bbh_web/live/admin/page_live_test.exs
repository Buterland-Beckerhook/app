defmodule BbhWeb.Admin.PageLiveTest do
  use BbhWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Bbh.ContentFixtures

  alias Bbh.Content

  setup :register_and_log_in_admin

  describe "Index" do
    test "lists pages", %{conn: conn} do
      page = page_fixture(title: "Über uns")
      {:ok, _lv, html} = live(conn, ~p"/admin/seiten")

      assert html =~ "Seiten"
      assert html =~ page.title
    end

    test "deletes a page from the edit page with slug confirmation", %{conn: conn} do
      page = page_fixture()
      {:ok, lv, _html} = live(conn, ~p"/admin/seiten/#{page.id}/bearbeiten")

      {:ok, _lv, html} =
        lv
        |> form("form[phx-submit=delete]", confirm: page.slug)
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/seiten")

      assert html =~ "Seite gelöscht"
      assert_raise Ecto.NoResultsError, fn -> Content.get_page!(page.id) end
    end
  end

  describe "Form (new)" do
    test "creates a page and redirects to its editor", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/seiten/neu")

      result =
        lv
        |> form("#page-form", page: %{title: "Geschichte", slug: "geschichte", status: "draft"})
        |> render_submit()

      # New pages redirect to their editor (to add content blocks).
      assert {:error, {:live_redirect, %{to: "/admin/seiten/" <> _}}} = result
      assert Bbh.Repo.get_by(Content.Page, slug: "geschichte")
    end
  end
end
