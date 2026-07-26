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

    test "the tree shows both levels at once, without navigating", %{conn: conn} do
      {:ok, presse} = Media.create_folder(%{"name" => "Presse"})
      {:ok, _} = Media.create_folder(%{"name" => "2026", "parent_id" => presse.id})
      {:ok, _} = Media.create_folder(%{"name" => "Satzungen"})

      {:ok, lv, html} = live(conn, ~p"/admin/medien")

      # Everything is on the page from the start — no expanding, no drilling in.
      assert html =~ "Presse"
      assert html =~ "2026"
      assert html =~ "Satzungen"
      assert has_element?(lv, ~s(#media-tree ul ul[data-subfolders]))
    end

    test "the tree follows the editor's order, not the alphabet", %{conn: conn} do
      # Deliberately move the alphabetically *later* folder to the front: with the
      # position column reverted this asserts the opposite of what name-ordering gives,
      # so it fails rather than passing by coincidence.
      {:ok, aktuelles} = Media.create_folder(%{"name" => "Aktuelles"})
      {:ok, archiv} = Media.create_folder(%{"name" => "Archiv"})

      {:ok, _} = Media.move_folder(archiv, nil, 0)

      {:ok, _lv, html} = live(conn, ~p"/admin/medien")

      assert index_of(html, ~s(data-folder-id="#{archiv.id}")) <
               index_of(html, ~s(data-folder-id="#{aktuelles.id}"))
    end

    test "creating from inside a sub-folder does what the hint promises", %{conn: conn} do
      {:ok, presse} = Media.create_folder(%{"name" => "Presse"})
      {:ok, child} = Media.create_folder(%{"name" => "2026", "parent_id" => presse.id})

      {:ok, lv, _html} = live(conn, ~p"/admin/medien?#{[folder: child.id]}")
      html = render_click(lv, "toggle_new_folder", %{})

      # A sub-folder cannot take children, so the hint says top level — and the create
      # has to agree instead of failing the depth check.
      assert html =~ "Neuer Ordner auf oberster Ebene"

      html = render_submit(lv, "create_folder", %{"name" => "Satzungen"})

      refute html =~ "zwei Ebenen tief"
      assert %{parent_id: nil} = Enum.find(Media.list_subfolders(nil), &(&1.name == "Satzungen"))
    end

    test "creating from inside a top-level folder makes a sub-folder", %{conn: conn} do
      {:ok, presse} = Media.create_folder(%{"name" => "Presse"})

      {:ok, lv, _html} = live(conn, ~p"/admin/medien?#{[folder: presse.id]}")
      html = render_click(lv, "toggle_new_folder", %{})
      assert html =~ "Neuer Unterordner in Presse"

      render_submit(lv, "create_folder", %{"name" => "2026"})

      assert ["2026"] == Media.list_subfolders(presse.id) |> Enum.map(& &1.name)
    end

    test "an unknown folder in the URL falls back to Alle Medien", %{conn: conn} do
      {:ok, folder} = Media.create_folder(%{"name" => "Presse"})
      filed = upload_fixture(folder_id: folder.id, filename: "im-ordner.webp")
      unfiled = upload_fixture(filename: "ohne-ordner.webp")

      # Both files, not just the unfiled one — otherwise a fallback to :unfiled would
      # pass this too.
      for url <- [
            ~p"/admin/medien?#{[folder: Ecto.UUID.generate()]}",
            ~p"/admin/medien?folder=keine-uuid"
          ] do
        {:ok, _lv, html} = live(conn, url)
        assert html =~ filed.filename
        assert html =~ unfiled.filename
      end
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

  describe "scope" do
    setup do
      {:ok, folder} = Media.create_folder(%{"name" => "Presse"})

      %{
        folder: folder,
        filed: upload_fixture(folder_id: folder.id, filename: "im-ordner.webp"),
        unfiled: upload_fixture(filename: "ohne-ordner.webp")
      }
    end

    test "Alle Medien lists filed and unfiled together", ctx do
      {:ok, _lv, html} = live(ctx.conn, ~p"/admin/medien")

      assert html =~ ctx.filed.filename
      assert html =~ ctx.unfiled.filename
    end

    test "Ohne Ordner lists only what is not in a folder", ctx do
      {:ok, _lv, html} = live(ctx.conn, ~p"/admin/medien?folder=none")

      assert html =~ ctx.unfiled.filename
      refute html =~ ctx.filed.filename
    end

    test "a folder lists only its own files", ctx do
      {:ok, _lv, html} = live(ctx.conn, ~p"/admin/medien?#{[folder: ctx.folder.id]}")

      assert html =~ ctx.filed.filename
      refute html =~ ctx.unfiled.filename
    end

    test "the tree counts what each node will show", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/admin/medien")

      # Addressed by attribute, not by "label … then a number somewhere after it" — the
      # latter passes on any stray digit between the two.
      assert has_element?(lv, ~s([data-node][data-folder-id="#{ctx.folder.id}"] [data-count="1"]))
      # Child-of-the-outer-list, so it cannot drift onto the first row of a nested
      # sub-folder list once the fixture grows one.
      assert has_element?(lv, ~s(#media-tree > ul > li:first-child [data-count="2"]))
    end
  end

  describe "drag & drop" do
    test "dropping a tile on a folder moves it and removes it from the grid", %{conn: conn} do
      {:ok, folder} = Media.create_folder(%{"name" => "Presse"})
      upload = upload_fixture(%{})

      # Browsing "Ohne Ordner", so the file leaves the current scope when it is filed.
      {:ok, lv, html} = live(conn, ~p"/admin/medien?folder=none")
      assert html =~ upload.filename

      html = render_hook(lv, "move_media", %{"id" => upload.id, "folder_id" => folder.id})

      assert Media.get_upload!(upload.id).folder_id == folder.id
      assert html =~ "nach „Presse“ verschoben"
      refute html =~ upload.filename
    end

    test "dropping a tile on Ohne Ordner unfiles it", %{conn: conn} do
      {:ok, folder} = Media.create_folder(%{"name" => "Presse"})
      upload = upload_fixture(folder_id: folder.id)

      {:ok, lv, _html} = live(conn, ~p"/admin/medien?#{[folder: folder.id]}")
      html = render_hook(lv, "move_media", %{"id" => upload.id, "folder_id" => ""})

      refute Media.get_upload!(upload.id).folder_id
      assert html =~ "aus dem Ordner entfernt"
    end

    test "a tile stays in the grid when Alle Medien is open", %{conn: conn} do
      {:ok, folder} = Media.create_folder(%{"name" => "Presse"})
      upload = upload_fixture(%{})

      {:ok, lv, _html} = live(conn, ~p"/admin/medien")
      html = render_hook(lv, "move_media", %{"id" => upload.id, "folder_id" => folder.id})

      # Nothing can fall out of "Alle Medien" — the tile is re-rendered, not dropped.
      assert html =~ upload.filename
    end

    test "dragging a folder reorders its level", %{conn: conn} do
      {:ok, a} = Media.create_folder(%{"name" => "A"})
      {:ok, _b} = Media.create_folder(%{"name" => "B"})
      {:ok, c} = Media.create_folder(%{"name" => "C"})

      {:ok, lv, _html} = live(conn, ~p"/admin/medien")
      html = render_hook(lv, "move_folder", %{"id" => c.id, "parent_id" => "", "position" => 0})

      assert ["C", "A", "B"] == Media.list_subfolders(nil) |> Enum.map(& &1.name)

      assert index_of(html, ~s(data-folder-id="#{c.id}")) <
               index_of(html, ~s(data-folder-id="#{a.id}"))
    end

    test "dragging a folder onto another nests it", %{conn: conn} do
      {:ok, a} = Media.create_folder(%{"name" => "A"})
      {:ok, b} = Media.create_folder(%{"name" => "B"})

      {:ok, lv, _html} = live(conn, ~p"/admin/medien")
      render_hook(lv, "move_folder", %{"id" => b.id, "parent_id" => a.id, "position" => 0})

      assert Media.get_folder(b.id).parent_id == a.id
    end

    test "a move the two-level cap forbids flashes an error and changes nothing", %{conn: conn} do
      {:ok, a} = Media.create_folder(%{"name" => "A"})
      {:ok, b} = Media.create_folder(%{"name" => "B"})
      {:ok, _child} = Media.create_folder(%{"name" => "2026", "parent_id" => a.id})

      {:ok, lv, _html} = live(conn, ~p"/admin/medien")
      html = render_hook(lv, "move_folder", %{"id" => a.id, "parent_id" => b.id, "position" => 0})

      assert html =~ "Unterordnern"
      refute Media.get_folder(a.id).parent_id
      assert ["A", "B"] == Media.list_subfolders(nil) |> Enum.map(& &1.name)
    end

    test "a crafted drop payload flashes instead of crashing the LiveView", %{conn: conn} do
      {:ok, a} = Media.create_folder(%{"name" => "A"})

      {:ok, lv, _html} = live(conn, ~p"/admin/medien")

      html =
        render_hook(lv, "move_folder", %{
          "id" => a.id,
          "parent_id" => "'; drop table media_folders; --",
          "position" => 0
        })

      assert html =~ "Zielordner nicht gefunden"
      refute Media.get_folder(a.id).parent_id
    end

    test "a stale folder id is ignored rather than crashing", %{conn: conn} do
      {:ok, a} = Media.create_folder(%{"name" => "A"})
      {:ok, b} = Media.create_folder(%{"name" => "B"})

      {:ok, lv, _html} = live(conn, ~p"/admin/medien")

      html =
        render_hook(lv, "move_folder", %{
          "id" => Ecto.UUID.generate(),
          "parent_id" => "",
          "position" => 0
        })

      # Nothing moved, and no complaint about a folder the editor never touched.
      # (`alert-error` is unusable as a marker — the disconnect toast ships it on every
      # page.) The move-folder failures all end in one of these two words.
      refute html =~ "nicht gefunden"
      refute html =~ "existiert"
      assert ["A", "B"] == Media.list_subfolders(nil) |> Enum.map(& &1.name)

      assert index_of(html, ~s(data-folder-id="#{a.id}")) <
               index_of(html, ~s(data-folder-id="#{b.id}"))
    end

    test "moving a tile into a folder that is gone flashes instead of crashing", %{conn: conn} do
      upload = upload_fixture(%{})
      {:ok, lv, _html} = live(conn, ~p"/admin/medien")

      html =
        render_hook(lv, "move_media", %{"id" => upload.id, "folder_id" => Ecto.UUID.generate()})

      assert html =~ "konnte nicht verschoben werden"
      refute Media.get_upload!(upload.id).folder_id
    end

    test "a crafted media drop payload flashes instead of crashing", %{conn: conn} do
      upload = upload_fixture(%{})
      {:ok, lv, _html} = live(conn, ~p"/admin/medien")

      # Ecto waves a malformed :binary_id through cast/3 and raises Ecto.ChangeError at
      # dump time — an exception, not a changeset error, so this would take the LiveView
      # down rather than flash.
      html = render_hook(lv, "move_media", %{"id" => upload.id, "folder_id" => "../../etc"})

      assert html =~ "konnte nicht verschoben werden"
      refute Media.get_upload!(upload.id).folder_id
    end

    test "a name already taken on the target level is refused in German", %{conn: conn} do
      {:ok, a} = Media.create_folder(%{"name" => "A"})
      {:ok, b} = Media.create_folder(%{"name" => "B"})
      {:ok, _} = Media.create_folder(%{"name" => "B", "parent_id" => a.id})

      # Nothing in the tree stops an editor dragging B onto A, so this is a live path.
      {:ok, lv, _html} = live(conn, ~p"/admin/medien")
      html = render_hook(lv, "move_folder", %{"id" => b.id, "parent_id" => a.id, "position" => 0})

      assert html =~ "existiert bereits"
      refute Media.get_folder(b.id).parent_id
    end

    test "moving the open folder updates the heading", %{conn: conn} do
      {:ok, presse} = Media.create_folder(%{"name" => "Presse"})
      {:ok, child} = Media.create_folder(%{"name" => "2026", "parent_id" => presse.id})

      {:ok, lv, html} = live(conn, ~p"/admin/medien?#{[folder: child.id]}")
      assert html =~ "Presse / 2026"

      html =
        render_hook(lv, "move_folder", %{"id" => child.id, "parent_id" => "", "position" => 0})

      # The heading specifically — "2026" also appears in the tree row either way.
      refute html =~ "Presse / 2026"
      assert html =~ ~r{<h2[^>]*>\s*2026\s*</h2>}
      refute Media.get_folder(child.id).parent_id
    end

    test "tiles and folder rows carry what the hooks need", %{conn: conn} do
      {:ok, folder} = Media.create_folder(%{"name" => "Presse"})
      upload = upload_fixture(%{})

      {:ok, lv, _html} = live(conn, ~p"/admin/medien")

      assert has_element?(lv, ~s(#media-tree[phx-hook="MediaTree"]))
      assert has_element?(lv, ~s(#media-grid[phx-hook="MediaGrid"]))

      assert has_element?(
               lv,
               ~s(#media-grid figure[data-media-id="#{upload.id}"][draggable="true"])
             )

      assert has_element?(
               lv,
               ~s([data-node][data-folder-id="#{folder.id}"][data-parent-id=""][data-accepts="folder media"])
             )

      assert has_element?(lv, ~s([data-node][data-folder-id="#{folder.id}"] [data-drag-handle]))

      # A stable id per row is what keeps keyboard focus on the folder — not the slot —
      # across the patch that follows a move.
      assert has_element?(lv, ~s(a#tree-node-#{folder.id}))
    end

    test "no inline event handlers reach the markup", %{conn: conn} do
      upload = upload_fixture(caption: "Mit Bildunterschrift")
      {:ok, folder} = Media.create_folder(%{"name" => "Presse"})
      {:ok, _} = Media.create_folder(%{"name" => "2026", "parent_id" => folder.id})

      {:ok, lv, html} = live(conn, ~p"/admin/medien")

      # The editor modal and the drop-target states are not in the initial render, so
      # scanning only that would miss a handler added to either.
      html = html <> render_click(lv, "edit", %{"id" => upload.id})
      html = html <> render_hook(lv, "move_media", %{"id" => upload.id, "folder_id" => folder.id})

      # Production CSP is nonce + strict-dynamic with no 'unsafe-inline', so an
      # ondragover="…" would silently do nothing there while passing dev and this suite.
      # Every `on…` attribute is an event handler and `phx-*` carries a hyphen, so the
      # broad form is safe — and catches onfocus/onerror/onmouseover too.
      refute html =~ ~r/\son[a-z]+=/i
    end
  end

  describe "page order" do
    test "upload comes first, then the tree, then the media", %{conn: conn} do
      {:ok, _} = Media.create_folder(%{"name" => "Presse"})
      {:ok, _lv, html} = live(conn, ~p"/admin/medien")

      assert index_of(html, ~s(id="upload-form")) < index_of(html, ~s(id="media-tree"))
      assert index_of(html, ~s(id="media-tree")) < index_of(html, ~s(id="media-grid"))
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

    test "the alt-text field shows the caption it falls back to", %{conn: conn} do
      upload = upload_fixture(caption: "Thronpaar 2025 auf dem Festplatz")

      {:ok, lv, _html} = live(conn, ~p"/admin/medien")
      html = render_click(lv, "edit", %{"id" => upload.id})

      assert has_element?(
               lv,
               ~s(textarea[name="upload[description]"][placeholder="Thronpaar 2025 auf dem Festplatz"])
             )

      assert html =~ "„Thronpaar 2025 auf dem Festplatz“ wird als Alt-Text benutzt"
    end

    test "with no caption the hint names the title, which is what is really used", %{conn: conn} do
      upload = upload_fixture(title: "Thron 2025 Rohscan")

      {:ok, lv, _html} = live(conn, ~p"/admin/medien")
      html = render_click(lv, "edit", %{"id" => upload.id})

      # image_alt/1 falls through caption to the *internal* title. Showing the actual
      # value makes that visible rather than surprising.
      assert html =~ "„Thron 2025 Rohscan“ wird als Alt-Text benutzt"
      assert BbhWeb.Format.image_alt(upload) == "Thron 2025 Rohscan"
    end

    test "no fallback hint when there is nothing to fall back to", %{conn: conn} do
      upload = upload_fixture(title: nil, caption: nil)

      {:ok, lv, _html} = live(conn, ~p"/admin/medien")
      html = render_click(lv, "edit", %{"id" => upload.id})

      assert html =~ "Datei bearbeiten"
      refute html =~ "wird als Alt-Text benutzt"
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

  # Where a fragment first appears in the rendered page — used to assert the order of
  # whole sections, which is what the layout change is actually about.
  defp index_of(html, fragment) do
    case :binary.match(html, fragment) do
      {position, _length} -> position
      :nomatch -> flunk("expected to find #{inspect(fragment)} in the page")
    end
  end
end
