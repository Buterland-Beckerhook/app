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

  describe "media_card block image" do
    test "selecting an image from the library sets it on the block", %{conn: conn} do
      page = page_fixture()
      {:ok, _} = Content.add_block(page, "media_card")
      upload = upload_fixture(filename: "karte.webp")

      {:ok, lv, _html} = live(conn, ~p"/admin/seiten/#{page.id}/bearbeiten")

      [{pb, _block}] = Content.load_blocks(Content.get_page!(page.id))

      render_click(lv, "open_image_picker", %{"pb_id" => pb.id})
      render_click(lv, "set_block_image", %{"pb_id" => pb.id, "media_id" => upload.id})

      [{_pb, block}] = Content.load_blocks(Content.get_page!(page.id))
      assert block.image_id == upload.id

      # And it can be cleared again.
      render_click(lv, "clear_block_image", %{"pb_id" => pb.id})
      [{_pb, block}] = Content.load_blocks(Content.get_page!(page.id))
      assert is_nil(block.image_id)
    end
  end
end
