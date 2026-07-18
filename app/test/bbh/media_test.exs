defmodule Bbh.MediaTest do
  # async: false — overrides the global :bbh, :uploads_dir and writes real files.
  use Bbh.DataCase

  alias Bbh.Content
  alias Bbh.Media
  alias Bbh.Media.{Folder, Upload}

  import Bbh.ContentFixtures, only: [upload_fixture: 1, article_fixture: 1]

  # 1×1 transparent PNG.
  @png Base.decode64!(
         "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
       )

  @pdf "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n1 0 obj<</Type/Catalog>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF"

  setup do
    tmp = Path.join(System.tmp_dir!(), "bbh_media_test_#{System.unique_integer([:positive])}")
    cache = Path.join(tmp, "cache")
    File.mkdir_p!(tmp)
    File.mkdir_p!(cache)
    prev = Application.get_env(:bbh, :uploads_dir)
    prev_cache = Application.get_env(:bbh, :media_cache_dir)
    Application.put_env(:bbh, :uploads_dir, tmp)
    Application.put_env(:bbh, :media_cache_dir, cache)

    on_exit(fn ->
      Application.put_env(:bbh, :uploads_dir, prev)
      Application.put_env(:bbh, :media_cache_dir, prev_cache)
      File.rm_rf(tmp)
    end)

    {:ok, tmp: tmp, cache: cache}
  end

  defp write_tmp(bytes) do
    path = Path.join(System.tmp_dir!(), "src_#{System.unique_integer([:positive])}")
    File.write!(path, bytes)
    on_exit(fn -> File.rm(path) end)
    path
  end

  describe "list_uploads/1" do
    test "filters by search across filename and title" do
      upload_fixture(filename: "sonnenblume.webp", title: "Blume")
      upload_fixture(filename: "auto.webp", title: "Fahrzeug")

      assert [%Upload{filename: "sonnenblume.webp"}] = Media.list_uploads(search: "blume")
      assert [%Upload{title: "Fahrzeug"}] = Media.list_uploads(search: "fahr")
      assert Media.list_uploads(search: "nichts") == []
    end

    test "sorts by name, oldest and newest" do
      a = upload_fixture(filename: "a.webp")
      b = upload_fixture(filename: "b.webp")
      # Backdate `a` so newest/oldest ordering is unambiguous (fixtures share a second).
      Repo.update_all(from(u in Upload, where: u.id == ^a.id),
        set: [inserted_at: ~U[2020-01-01 00:00:00Z]]
      )

      assert [%{id: first}, %{id: second}] = Media.list_uploads(sort: "name")
      assert [first, second] == [a.id, b.id]
      assert [%{id: oldest} | _] = Media.list_uploads(sort: "oldest")
      assert oldest == a.id
      assert [%{id: newest} | _] = Media.list_uploads(sort: "newest")
      assert newest == b.id
    end
  end

  describe "get_upload!/1 and update_upload/2" do
    test "fetches and updates" do
      upload = upload_fixture(%{})
      assert Media.get_upload!(upload.id).id == upload.id
      assert {:ok, updated} = Media.update_upload(upload, %{title: "Neuer Titel"})
      assert updated.title == "Neuer Titel"
    end

    test "ignores system fields in update params (mass-assignment guard)", %{tmp: tmp} do
      src = write_tmp(@png)
      {:ok, upload} = Media.store_file(src, %{filename: "x.png"})
      original_key = upload.storage_key

      # A crafted form event carrying extra keys must not repoint the stored file:
      # storage_key drives File.rm/send_file, so overwriting it with "../.." would
      # let an admin escape uploads_dir.
      {:ok, updated} =
        Media.update_upload(upload, %{
          "title" => "Neu",
          "storage_key" => "../../../../etc/passwd",
          "content_type" => "text/html"
        })

      assert updated.title == "Neu"
      assert updated.storage_key == original_key
      assert updated.content_type == "image/png"
      assert Path.join(tmp, updated.storage_key) |> File.regular?()
    end
  end

  describe "Upload.changeset/2 storage_key validation" do
    test "rejects a storage key that would escape uploads_dir" do
      for bad <- ["../../etc/passwd", "/etc/passwd", "a/../b", "..", ""] do
        cs = Upload.changeset(%Upload{}, %{storage_key: bad, filename: "x.png"})
        refute cs.valid?, "expected #{inspect(bad)} to be rejected"
      end
    end

    test "accepts the generated key shape" do
      cs =
        Upload.changeset(%Upload{}, %{
          storage_key: "2026/#{Ecto.UUID.generate()}.webp",
          filename: "x"
        })

      assert cs.valid?
    end
  end

  describe "delete_upload/1" do
    test "removes the row and the original file", %{tmp: tmp} do
      src = write_tmp(@png)
      {:ok, upload} = Media.store_file(src, %{filename: "x.png"})
      stored = Path.join(tmp, upload.storage_key)
      assert File.regular?(stored)

      assert {:ok, _} = Media.delete_upload(upload)
      refute File.regular?(stored)
      refute Repo.get(Upload, upload.id)
    end
  end

  describe "store_file/2" do
    test "stores a real image and derives type/extension from the bytes" do
      src = write_tmp(@png)

      # Client claims an executable name/type — must be ignored in favour of the bytes.
      assert {:ok, upload} =
               Media.store_file(src, %{
                 filename: "evil.exe",
                 content_type: "application/x-msdownload"
               })

      assert upload.content_type == "image/png"
      assert String.ends_with?(upload.storage_key, ".png")
      assert upload.filename == "evil.exe"
    end

    test "rejects a non-image whose extension is spoofed" do
      src = write_tmp("this is definitely not an image")
      assert {:error, :unsupported_media_type} = Media.store_file(src, %{filename: "fake.png"})
    end

    test "stores a PDF as a document (no image variant, no dimensions)" do
      src = write_tmp(@pdf)

      assert {:ok, upload} = Media.store_file(src, %{filename: "satzung.pdf"})
      assert upload.content_type == "application/pdf"
      assert String.ends_with?(upload.storage_key, ".pdf")
      assert is_nil(upload.width) and is_nil(upload.height)
      refute Media.image?(upload)
    end

    test "rejects an image whose pixel count exceeds the megapixel budget", %{tmp: tmp} do
      # Drive the budget below the 1×1 fixture so a real (tiny) image trips the
      # guard — the same code path a decompression bomb hits, without needing one.
      prev = Application.get_env(:bbh, :max_image_pixels)
      Application.put_env(:bbh, :max_image_pixels, 0)
      on_exit(fn -> Application.put_env(:bbh, :max_image_pixels, prev) end)

      src = write_tmp(@png)
      assert {:error, :image_too_large} = Media.store_file(src, %{filename: "bomb.png"})

      # Rejected before anything landed in the uploads dir (only the cache subdir).
      assert File.ls!(tmp) == ["cache"]
    end
  end

  describe "delete_upload/1 with references" do
    test "refuses to delete media that is still used by an article" do
      upload = upload_fixture(%{})
      article = article_fixture(%{})
      {:ok, _} = Content.add_article_image(article, upload.id)

      assert Media.in_use?(upload)
      assert [{:articles, 1}] = Media.usages(upload)
      assert {:error, :in_use} = Media.delete_upload(upload)
      assert Media.get_upload!(upload.id)
    end
  end

  describe "folders" do
    test "creates two levels but rejects a third" do
      {:ok, root} = Media.create_folder(%{"name" => "Dokumente"})
      assert is_nil(root.parent_id)

      {:ok, sub} = Media.create_folder(%{"name" => "2026", "parent_id" => root.id})
      assert sub.parent_id == root.id

      assert {:error, changeset} =
               Media.create_folder(%{"name" => "zu-tief", "parent_id" => sub.id})

      assert %{parent_id: [_]} = errors_on(changeset)
    end

    test "rejects duplicate names within the same parent" do
      {:ok, _} = Media.create_folder(%{"name" => "Bilder"})
      assert {:error, changeset} = Media.create_folder(%{"name" => "Bilder"})
      assert %{name: [_]} = errors_on(changeset)
    end

    test "filters uploads by folder and moves them between folders" do
      {:ok, folder} = Media.create_folder(%{"name" => "Presse"})
      filed = upload_fixture(folder_id: folder.id)
      _unfiled = upload_fixture(%{})

      assert [%{id: id}] = Media.list_uploads(folder: folder.id)
      assert id == filed.id
      assert [_only_root] = Media.list_uploads(folder: :root)

      {:ok, moved} = Media.move_upload(filed, nil)
      assert is_nil(moved.folder_id)
      assert Media.list_uploads(folder: folder.id) == []
    end

    test "deleting a folder unfiles its media" do
      {:ok, folder} = Media.create_folder(%{"name" => "Alt"})
      upload = upload_fixture(folder_id: folder.id)

      {:ok, _} = Media.delete_folder(folder)

      assert Repo.get!(Upload, upload.id).folder_id == nil
      refute Repo.get(Folder, folder.id)
    end
  end

  describe "resolve_variant/3" do
    test "rejects path traversal in the storage key" do
      assert Media.resolve_variant("../../etc/passwd", nil, nil) == :error
    end

    test "returns :error for a missing key" do
      assert Media.resolve_variant("nope/missing.png", 100, 100) == :error
    end

    test "serves the original when no dimensions are requested" do
      src = write_tmp(@png)
      {:ok, upload} = Media.store_file(src, %{filename: "x.png"})

      assert {:ok, path, "image/png"} = Media.resolve_variant(upload.storage_key, nil, nil)
      assert File.regular?(path)
    end

    test "generates a cached WebP variant from the source path (shrink-on-load)" do
      src = write_tmp(@png)
      {:ok, upload} = Media.store_file(src, %{filename: "x.png"})

      assert {:ok, path, "image/webp"} = Media.resolve_variant(upload.storage_key, 100, 100)
      assert File.regular?(path)
      assert String.ends_with?(path, ".webp")

      # Second request is served from cache (identical path), not regenerated.
      assert {:ok, ^path, "image/webp"} = Media.resolve_variant(upload.storage_key, 100, 100)
    end
  end
end
