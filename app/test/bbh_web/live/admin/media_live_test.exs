defmodule BbhWeb.Admin.MediaLiveTest do
  # async: false — the upload tests override the global :bbh, :uploads_dir and write files.
  use BbhWeb.ConnCase

  import Phoenix.LiveViewTest
  import Bbh.ContentFixtures

  alias Bbh.Media

  # 1×1 transparent PNG.
  @png Base.decode64!(
         "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
       )

  setup :register_and_log_in_admin

  setup do
    tmp = Path.join(System.tmp_dir!(), "bbh_medialive_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    prev = Application.get_env(:bbh, :uploads_dir)
    Application.put_env(:bbh, :uploads_dir, tmp)

    on_exit(fn ->
      Application.put_env(:bbh, :uploads_dir, prev)
      File.rm_rf(tmp)
    end)

    :ok
  end

  test "renders the media library with existing uploads", %{conn: conn} do
    upload = upload_fixture(filename: "wappen.webp", title: "Wappen")
    {:ok, _lv, html} = live(conn, ~p"/admin/medien")

    assert html =~ "Medien"
    assert html =~ upload.filename
  end

  test "filters uploads by search", %{conn: conn} do
    upload_fixture(filename: "sonne.webp")
    upload_fixture(filename: "mond.webp")

    {:ok, lv, _html} = live(conn, ~p"/admin/medien")
    html = render_change(lv, "filter", %{"search" => "sonne", "sort" => "newest"})

    assert html =~ "sonne.webp"
    refute html =~ "mond.webp"
  end

  test "deletes an upload", %{conn: conn} do
    upload = upload_fixture(%{})
    {:ok, lv, _html} = live(conn, ~p"/admin/medien")

    render_click(lv, "delete", %{"id" => upload.id})

    assert_raise Ecto.NoResultsError, fn -> Media.get_upload!(upload.id) end
  end

  describe "upload flow" do
    test "uploads a valid image and inserts it into the stream", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/medien")

      file =
        file_input(lv, "#upload-form", :files, [
          %{name: "wappen.png", content: @png, type: "image/png"}
        ])

      assert render_upload(file, "wappen.png") =~ "wappen.png"

      html = lv |> element("#upload-form") |> render_submit()

      assert html =~ "hochgeladen"
      assert [%{filename: "wappen.png", content_type: "image/png"}] = Media.list_uploads()
    end

    test "rejects a file whose bytes are not a real image", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/medien")

      file =
        file_input(lv, "#upload-form", :files, [
          %{name: "fake.png", content: "definitely not an image", type: "image/png"}
        ])

      render_upload(file, "fake.png")
      html = lv |> element("#upload-form") |> render_submit()

      assert html =~ "abgelehnt (kein gültiges Bild/PDF)"
      assert Media.list_uploads() == []
    end
  end

  describe "folders" do
    test "creates a folder and navigates into it", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/medien")

      render_click(lv, "toggle_new_folder", %{})
      render_submit(lv, "create_folder", %{"name" => "Satzungen"})

      assert [folder] = Media.list_subfolders(nil)
      assert folder.name == "Satzungen"

      {:ok, _lv, html} = live(conn, ~p"/admin/medien?#{[folder: folder.id]}")
      assert html =~ "Satzungen"
    end

    test "editing an item saves metadata and moves it to a folder", %{conn: conn} do
      {:ok, folder} = Media.create_folder(%{"name" => "Presse"})
      upload = upload_fixture(%{})
      {:ok, lv, _html} = live(conn, ~p"/admin/medien")

      render_click(lv, "edit", %{"id" => upload.id})

      render_submit(lv, "save_meta", %{
        "upload" => %{
          "title" => "Neuer Titel",
          "description" => "Beschreibung",
          "copyright" => "BBH",
          "folder_id" => folder.id
        }
      })

      updated = Media.get_upload!(upload.id)
      assert updated.title == "Neuer Titel"
      assert updated.copyright == "BBH"
      assert updated.folder_id == folder.id
    end
  end

  describe "editor" do
    test "rotating turns the stored original and keeps the editor open", %{conn: conn} do
      {:ok, img} = Image.new(400, 200, color: [10, 120, 60])
      src = Path.join(System.tmp_dir!(), "wide_#{System.unique_integer([:positive])}.png")
      {:ok, _} = Image.write(img, src)
      on_exit(fn -> File.rm(src) end)
      {:ok, upload} = Media.store_file(src, %{filename: "wide.png"})

      {:ok, lv, _html} = live(conn, ~p"/admin/medien")
      render_click(lv, "edit", %{"id" => upload.id})

      # The "Rechts" button is a submit that carries the angle, so a turn also saves
      # whatever is typed in the form.
      assert has_element?(lv, ~s(#media-edit-form button[name="rotate"][value="90"]))

      html =
        lv
        |> form("#media-edit-form", upload: %{caption: "Gedreht"})
        |> render_submit(%{"rotate" => "90"})

      assert html =~ "Bild gedreht"
      # Still in the editor, so another turn is one click away.
      assert html =~ "Datei bearbeiten"

      rotated = Media.get_upload!(upload.id)
      assert {rotated.width, rotated.height} == {200, 400}
      assert rotated.revision == 1
      # Metadata typed before the turn is not lost.
      assert rotated.caption == "Gedreht"
    end

    test "no rotate buttons for a PDF", %{conn: conn} do
      pdf = Path.join(System.tmp_dir!(), "doc_#{System.unique_integer([:positive])}.pdf")
      File.write!(pdf, "%PDF-1.4\n%\xE2\xE3\xCF\xD3\ntrailer<</Root 1 0 R>>\n%%EOF")
      on_exit(fn -> File.rm(pdf) end)
      {:ok, upload} = Media.store_file(pdf, %{filename: "satzung.pdf"})

      {:ok, lv, _html} = live(conn, ~p"/admin/medien")
      html = render_click(lv, "edit", %{"id" => upload.id})

      assert html =~ "Datei bearbeiten"
      refute html =~ ~s(name="rotate")
    end

    test "saves the caption and closes", %{conn: conn} do
      upload = upload_fixture(%{})
      {:ok, lv, _html} = live(conn, ~p"/admin/medien")
      render_click(lv, "edit", %{"id" => upload.id})

      html =
        lv
        |> form("#media-edit-form", upload: %{caption: "Der Thron 2025", copyright: "BBH e.V."})
        |> render_submit()

      refute html =~ "Datei bearbeiten"
      updated = Media.get_upload!(upload.id)
      assert updated.caption == "Der Thron 2025"
      assert updated.copyright == "BBH e.V."
    end
  end

  test "refuses to delete media that is still in use", %{conn: conn} do
    upload = upload_fixture(%{})
    article = article_fixture(%{})
    {:ok, _} = Bbh.Content.add_article_image(article, upload.id)

    {:ok, lv, _html} = live(conn, ~p"/admin/medien")
    html = render_click(lv, "delete", %{"id" => upload.id})

    assert html =~ "wird noch verwendet"
    assert Media.get_upload!(upload.id)
  end
end
