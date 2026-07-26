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

      open_picker(lv, "media_card", pb.id)
      pick(lv, upload.id)

      [{_pb, block}] = Content.load_blocks(Content.get_page!(page.id))
      assert block.image_id == upload.id

      # And it can be cleared again.
      render_click(lv, "clear_block_image", %{"pb_id" => pb.id})
      [{_pb, block}] = Content.load_blocks(Content.get_page!(page.id))
      assert is_nil(block.image_id)
    end
  end

  describe "image_gallery block images" do
    setup %{conn: conn} do
      page = page_fixture()
      {:ok, _} = Content.add_block(page, "image_gallery")
      [{pb, _gallery}] = Content.load_blocks(Content.get_page!(page.id))
      {:ok, lv, _html} = live(conn, ~p"/admin/seiten/#{page.id}/bearbeiten")

      %{page: page, pb: pb, lv: lv}
    end

    defp gallery_files(page), do: Content.load_blocks(Content.get_page!(page.id)) |> gallery_of()
    defp gallery_of([{_pb, gallery}]), do: gallery.files

    test "adds images from the library, in the order they were picked", ctx do
      first = upload_fixture(filename: "eins.webp")
      second = upload_fixture(filename: "zwei.webp")

      open_picker(ctx.lv, "gallery", ctx.pb.id)
      pick(ctx.lv, first.id)
      # The modal stays open, so the next image is one click away.
      pick(ctx.lv, second.id)

      assert Enum.map(gallery_files(ctx.page), & &1.media.filename) == ["eins.webp", "zwei.webp"]

      # Both appear in the block's own panel — asserting on the filenames alone would
      # also match the picker grid, which is still open behind the modal.
      for file <- gallery_files(ctx.page) do
        assert has_element?(
                 ctx.lv,
                 ~s(button[phx-click="remove_gallery_file"][phx-value-file_id="#{file.id}"])
               )
      end
    end

    test "reorders and removes images", ctx do
      first = upload_fixture(filename: "eins.webp")
      second = upload_fixture(filename: "zwei.webp")

      open_picker(ctx.lv, "gallery", ctx.pb.id)
      pick(ctx.lv, first.id)
      pick(ctx.lv, second.id)

      [_a, b] = gallery_files(ctx.page)

      ctx.lv
      |> element(
        ~s(button[phx-click="move_gallery_file"][phx-value-file_id="#{b.id}"][phx-value-dir="up"])
      )
      |> render_click()

      assert Enum.map(gallery_files(ctx.page), & &1.media.filename) == ["zwei.webp", "eins.webp"]

      ctx.lv
      |> element(~s(button[phx-click="remove_gallery_file"][phx-value-file_id="#{b.id}"]))
      |> render_click()

      assert Enum.map(gallery_files(ctx.page), & &1.media.filename) == ["eins.webp"]
    end
  end

  describe "media picker contract" do
    test "every picker button on this form has a matching handler", %{conn: conn} do
      page = page_fixture()
      # One of each block type that can hold an image.
      {:ok, _} = Content.add_block(page, "media_card")
      {:ok, _} = Content.add_block(page, "image_gallery")
      upload = upload_fixture(%{})

      {:ok, lv, html} = live(conn, ~p"/admin/seiten/#{page.id}/bearbeiten")

      buttons =
        html
        |> LazyHTML.from_document()
        |> LazyHTML.query(~s([phx-target="#media-picker"][phx-click="open"]))
        |> LazyHTML.attribute("phx-value-context")

      # A canary: bump this only together with a new handle_info clause in the form.
      assert length(buttons) == 2

      # An unhandled context would raise FunctionClauseError in handle_info/2 and kill the
      # LiveView, so surviving a pick from every button *is* the assertion.
      for context <- buttons do
        lv |> element(~s(button[phx-value-context="#{context}"])) |> render_click()
        lv |> element(~s(#media-picker button[phx-value-id="#{upload.id}"])) |> render_click()
        assert render(lv) =~ "Inhaltsblöcke"
      end
    end
  end

  # The shared picker (BbhWeb.Admin.MediaPicker) owns its own state, so it is driven
  # through its own elements; a pick reaches the page LiveView as a message, hence the
  # render/1 to synchronize before asserting.
  defp open_picker(lv, context, pb_id) do
    lv
    |> element(~s(button[phx-value-context="#{context}"][phx-value-pb_id="#{pb_id}"]))
    |> render_click()
  end

  defp pick(lv, media_id) do
    lv |> element(~s(#media-picker button[phx-value-id="#{media_id}"])) |> render_click()
    render(lv)
  end
end
