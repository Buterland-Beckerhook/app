defmodule BbhWeb.Admin.MediaPickerTest do
  use BbhWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Bbh.ContentFixtures

  alias Bbh.Media
  alias Bbh.Media.Upload
  alias BbhWeb.Admin.MediaPicker, as: Picker

  describe "insert_html/1" do
    test "images become an <img> with the media item's alt text, escaped" do
      upload = %Upload{storage_key: "abc.jpg", content_type: "image/jpeg", description: "A & B"}
      assert Picker.insert_html(upload) == ~s(<img src="/media/abc.jpg" alt="A &amp; B">)
    end

    test "alt text falls back through caption and title" do
      upload = %Upload{storage_key: "x.png", content_type: "image/png", caption: "Der Thron"}
      assert Picker.insert_html(upload) =~ ~s(alt="Der Thron")

      upload = %Upload{storage_key: "x.png", content_type: "image/png", title: "Wappen"}
      assert Picker.insert_html(upload) =~ ~s(alt="Wappen")
    end

    test "non-images become a download link" do
      upload = %Upload{storage_key: "doc.pdf", content_type: "application/pdf", title: "Satzung"}
      assert Picker.insert_html(upload) == ~s(<a href="/media/doc.pdf">Satzung</a>)
    end

    test "a rotated image carries its cache-busting revision" do
      upload = %Upload{storage_key: "abc.jpg", content_type: "image/jpeg", revision: 3}
      assert Picker.insert_html(upload) =~ ~s(src="/media/abc.jpg?v=3")
    end
  end

  # Driven through the article form, which mounts the picker as "#media-picker".
  describe "browsing (in the article form)" do
    setup :register_and_log_in_admin

    setup do
      {:ok, folder} = Media.create_folder(%{"name" => "Schützenfest"})
      {:ok, sub} = Media.create_folder(%{"name" => "2025", "parent_id" => folder.id})

      %{
        folder: folder,
        sub: sub,
        unfiled: upload_fixture(filename: "unsortiert.webp"),
        filed: upload_fixture(filename: "umzug.webp", folder_id: folder.id),
        nested: upload_fixture(filename: "zapfenstreich.webp", folder_id: sub.id),
        article: article_fixture()
      }
    end

    defp open_picker(conn, article) do
      {:ok, lv, _html} = live(conn, ~p"/admin/artikel/#{article.id}/bearbeiten")
      html = lv |> element(~s(button[phx-value-context="article_image"])) |> render_click()
      {lv, html}
    end

    # The picker owns its state, so every interaction goes through its own elements
    # (they carry phx-target) rather than the host LiveView.
    defp browse(lv, folder_id) do
      lv
      |> element(~s(#media-picker button[phx-value-folder_id="#{folder_id}"]))
      |> render_click()
    end

    # A pick reaches the host LiveView as a message, so render/1 afterwards to let it be
    # handled before asserting.
    defp pick(lv, media_id) do
      lv |> element(~s(#media-picker button[phx-value-id="#{media_id}"])) |> render_click()
      render(lv)
    end

    test "opens at the root: unfiled files plus the top-level folders", ctx do
      {_lv, html} = open_picker(ctx.conn, ctx.article)

      assert html =~ "Aus Mediathek wählen"
      assert html =~ "unsortiert.webp"
      assert html =~ "Schützenfest"
      # Files inside a folder are not dumped into the root listing.
      refute html =~ "umzug.webp"
    end

    test "entering a folder shows its files and its sub-folders", ctx do
      {lv, _html} = open_picker(ctx.conn, ctx.article)

      html = browse(lv, ctx.folder.id)

      assert html =~ "umzug.webp"
      assert html =~ "2025"
      refute html =~ "unsortiert.webp"

      # ADR 0007: the library browses a whole branch, the picker walks a path. A
      # sub-folder's files stay behind the chip that leads to them — otherwise they would
      # appear twice, here and one click deeper.
      refute html =~ ctx.nested.filename

      # And one level deeper.
      html = browse(lv, ctx.sub.id)
      assert html =~ "zapfenstreich.webp"
      refute html =~ "umzug.webp"
    end

    test "searching reaches across folders", ctx do
      {lv, _html} = open_picker(ctx.conn, ctx.article)

      html = lv |> form("#media-picker-search", %{"search" => "zapfen"}) |> render_change()

      assert html =~ "zapfenstreich.webp"
      refute html =~ "unsortiert.webp"
    end

    test "picking a file sets the article image and closes the modal", ctx do
      {lv, _html} = open_picker(ctx.conn, ctx.article)

      html = pick(lv, ctx.unfiled.id)

      assert Bbh.Content.get_article!(ctx.article.id).image_id == ctx.unfiled.id
      # Closed, because the article image is a single-image slot.
      refute html =~ "Aus Mediathek wählen"
    end

    test "closing hides the modal", ctx do
      {lv, _html} = open_picker(ctx.conn, ctx.article)

      html = lv |> element(~s(#media-picker button[aria-label="Schließen"])) |> render_click()
      refute html =~ "Aus Mediathek wählen"
    end

    test "every picker button on the article form has a matching handler", ctx do
      {:ok, lv, html} = live(ctx.conn, ~p"/admin/artikel/#{ctx.article.id}/bearbeiten")

      contexts =
        html
        |> LazyHTML.from_document()
        |> LazyHTML.query(~s([phx-target="#media-picker"][phx-click="open"]))
        |> LazyHTML.attribute("phx-value-context")

      # A canary: bump this only together with a new handle_info clause in the form.
      assert contexts == ["article_image"]

      # An unhandled context would raise FunctionClauseError in handle_info/2 and take the
      # LiveView down, so surviving a pick from every button *is* the assertion.
      for context <- contexts do
        lv |> element(~s(button[phx-value-context="#{context}"])) |> render_click()

        lv
        |> element(~s(#media-picker button[phx-value-id="#{ctx.unfiled.id}"]))
        |> render_click()

        assert render(lv) =~ "Artikelbild"
      end
    end
  end

  # The event form deliberately handles *no* selection message: its picker is opened by the
  # JS toolbar hook, which the component answers itself. That is the "or none at all" half
  # of the host contract, and it only holds while the form renders no picker button of its
  # own — a button there would be a silent no-op rather than a crash.
  #
  # The person form used to be the second such host. It now has a Portrait button and a
  # matching `handle_info/2`; its side of the contract is checked in `person_live_test.exs`.
  describe "Trix-only hosts" do
    setup :register_and_log_in_admin

    test "the event form mounts the picker without any context button", ctx do
      location = Bbh.CalendarFixtures.location_fixture()
      event = Bbh.CalendarFixtures.event_fixture(location_id: location.id)

      {:ok, _lv, html} = live(ctx.conn, ~p"/admin/termine/#{event.id}/bearbeiten")
      document = LazyHTML.from_document(html)

      assert LazyHTML.query(document, "#media-picker") |> Enum.any?()

      assert document
             |> LazyHTML.query(~s([phx-target="#media-picker"][phx-click="open"]))
             |> Enum.empty?()
    end
  end
end
