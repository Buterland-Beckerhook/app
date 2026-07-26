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

  # WebP is lossy, so a "red" pixel is only nearly red — compare by dominance.
  defp red?([r, g, b | _]), do: r > 150 and g < 100 and b < 100
  defp blue?([r, g, b | _]), do: b > 150 and r < 100 and g < 100

  # A real w×h PNG, so focal crops actually have pixels to reposition.
  defp write_image(w, h) do
    {:ok, img} = Image.new(w, h, color: [200, 50, 50])
    path = Path.join(System.tmp_dir!(), "src_#{System.unique_integer([:positive])}.png")
    {:ok, _} = Image.write(img, path)
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
          "content_type" => "text/html",
          # revision drives cache busting and is bumped only by rotate_upload/2.
          "revision" => 99
        })

      assert updated.title == "Neu"
      assert updated.storage_key == original_key
      assert updated.content_type == "image/png"
      assert updated.revision == 0
      assert Path.join(tmp, updated.storage_key) |> File.regular?()
    end

    test "edits the caption (Bildunterschrift) along with the other metadata" do
      upload = upload_fixture(%{})

      assert {:ok, updated} =
               Media.update_upload(upload, %{
                 "title" => "Schützenfest",
                 "caption" => "Der Thron 2025",
                 "description" => "Vier Personen in Uniform",
                 "copyright" => "BBH e.V."
               })

      assert updated.caption == "Der Thron 2025"
      assert updated.description == "Vier Personen in Uniform"
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

    test "also drops the cached variants (no orphans left behind)" do
      src = write_image(60, 40)
      {:ok, upload} = Media.store_file(src, %{filename: "x.png"})
      assert {:ok, variant, _} = Media.resolve_variant(upload.storage_key, 20, 20)
      assert File.regular?(variant)

      assert {:ok, _} = Media.delete_upload(upload)
      refute File.regular?(variant)
    end
  end

  describe "rotate_upload/2" do
    test "turns a landscape image portrait and bumps the revision", %{tmp: tmp} do
      src = write_image(400, 200)
      {:ok, upload} = Media.store_file(src, %{filename: "wide.png"})
      assert {upload.width, upload.height} == {400, 200}

      assert {:ok, rotated} = Media.rotate_upload(upload, 90)

      # The database …
      assert {rotated.width, rotated.height} == {200, 400}
      assert rotated.revision == upload.revision + 1

      # … and the stored original itself.
      {:ok, img} = Image.open(Path.join(tmp, rotated.storage_key))
      assert {Image.width(img), Image.height(img)} == {200, 400}
    end

    test "carries the focal point around with the image" do
      src = write_image(400, 200)
      {:ok, upload} = Media.store_file(src, %{filename: "wide.png"})
      {:ok, upload} = Media.update_upload(upload, %{focal_point_x: 0.9, focal_point_y: 0.5})

      # 90° clockwise maps (x, y) -> (1 - y, x).
      assert {:ok, cw} = Media.rotate_upload(upload, 90)
      assert {cw.focal_point_x, cw.focal_point_y} == {0.5, 0.9}

      assert {:ok, flipped} = Media.rotate_upload(upload, 180)
      assert {flipped.focal_point_x, flipped.focal_point_y} == {0.1, 0.5}
    end

    test "leaves a centered image without a focal point alone" do
      src = write_image(40, 20)
      {:ok, upload} = Media.store_file(src, %{filename: "wide.png"})

      assert {:ok, rotated} = Media.rotate_upload(upload, 270)
      assert is_nil(rotated.focal_point_x) and is_nil(rotated.focal_point_y)
    end

    test "turns the pixels clockwise, takes the focal point along, and serves the new bytes",
         %{tmp: tmp} do
      # Left half red, right half blue — so "which way did it turn?" is answerable.
      {:ok, base} = Image.new(40, 20, color: [255, 0, 0])
      {:ok, halves} = Image.Draw.rect(base, 20, 0, 20, 20, color: [0, 0, 255])
      src = Path.join(System.tmp_dir!(), "halves_#{System.unique_integer([:positive])}.png")
      {:ok, _} = Image.write(halves, src)
      on_exit(fn -> File.rm(src) end)

      {:ok, upload} = Media.store_file(src, %{filename: "halves.png"})
      {:ok, upload} = Media.update_upload(upload, %{focal_point_x: 0.1, focal_point_y: 0.5})

      # Warm the libvips operation cache on this filename — that cache is keyed by name
      # and does not notice the bytes changing underneath.
      assert {:ok, _, _} = Media.resolve_variant(upload.storage_key, 10, 10)

      assert {:ok, rotated} = Media.rotate_upload(upload, 90)

      # This is what pins flush_vips_cache/0: store_rotation/3 re-reads the size with
      # Image.open, which without the flush hands back the pre-rotation image.
      assert {rotated.width, rotated.height} == {20, 40}

      # 90° clockwise: the red left half becomes the top half.
      {:ok, on_disk} = Image.open(Path.join(tmp, rotated.storage_key))
      assert red?(Image.get_pixel!(on_disk, 5, 2))
      assert blue?(Image.get_pixel!(on_disk, 5, Image.height(on_disk) - 3))

      # The focal point rode along with it: x=0.1 sat in the red half, now y=0.1 does.
      assert {rotated.focal_point_x, rotated.focal_point_y} == {0.5, 0.1}

      # A regenerated variant shows the new orientation — this pins purge_variants/1 plus
      # the revision in the cache key, not the vips flush (Image.thumbnail on a path is
      # non-cacheable, so it never served stale bytes).
      assert {:ok, path, _} = Media.resolve_variant(rotated.storage_key, 10, 20)
      {:ok, thumb} = Image.open(path)
      assert red?(Image.get_pixel!(thumb, 5, 2))
      assert blue?(Image.get_pixel!(thumb, 5, 17))
    end

    test "bakes in EXIF orientation instead of stacking a second rotation on it" do
      # Orientation 6 = "display this rotated 90° clockwise", so a viewer shows the 40×20
      # source as 20×40 before we touch it.
      {:ok, base} = Image.new(40, 20, color: [200, 50, 50])

      {:ok, oriented} =
        Vix.Vips.Image.mutate(base, fn mut ->
          :ok = Vix.Vips.MutableImage.set(mut, "orientation", :gint, 6)
        end)

      src = Path.join(System.tmp_dir!(), "exif_#{System.unique_integer([:positive])}.jpg")
      {:ok, _} = Image.write(oriented, src)
      on_exit(fn -> File.rm(src) end)

      {:ok, upload} = Media.store_file(src, %{filename: "exif.jpg"})
      assert {:ok, rotated} = Media.rotate_upload(upload, 90)

      # Upright is 20×40; one more quarter turn makes it 40×20. Without autorotate the
      # tag would survive and a viewer would apply it *again* on top of our rotation.
      assert {rotated.width, rotated.height} == {40, 20}
      # vips normalises the tag while baking it in; it must no longer ask a viewer to turn
      # the image a second time.
      path = Path.join(Media.uploads_dir(), rotated.storage_key)
      assert {:ok, exif} = Image.exif(Image.open!(path))
      assert Map.get(exif, :orientation) in [nil, 1, "Horizontal (normal)"]
    end

    test "purges the cached variants so nothing serves the old orientation" do
      src = write_image(400, 200)
      {:ok, upload} = Media.store_file(src, %{filename: "wide.png"})
      assert {:ok, variant, _} = Media.resolve_variant(upload.storage_key, 100, 100)
      assert File.regular?(variant)

      assert {:ok, _} = Media.rotate_upload(upload, 90)
      refute File.regular?(variant)

      # The regenerated variant lands on a *different* path — the revision joins the
      # cache key, so nothing can be served from the pre-rotation name again.
      assert {:ok, regenerated, _} = Media.resolve_variant(upload.storage_key, 100, 100)
      assert regenerated != variant
      assert File.regular?(regenerated)
    end

    test "a variant written after the purge (a generation still in flight) is never served" do
      src = write_image(400, 200)
      {:ok, upload} = Media.store_file(src, %{filename: "wide.png"})
      assert {:ok, stale, _} = Media.resolve_variant(upload.storage_key, 100, 100)

      assert {:ok, _} = Media.rotate_upload(upload, 90)

      # Replay the race: a generation that started before the rename finishes after the
      # purge and writes the pre-rotation image back under its old name.
      File.mkdir_p!(Path.dirname(stale))
      File.write!(stale, "stale bytes from before the rotation")

      assert {:ok, served, _} = Media.resolve_variant(upload.storage_key, 100, 100)
      refute served == stale
      # Whatever is served is a real image, not the resurrected file.
      assert {:ok, _} = Image.open(served)
    end

    test "four quarter turns come back to the original dimensions" do
      src = write_image(400, 200)
      {:ok, upload} = Media.store_file(src, %{filename: "wide.png"})

      final =
        Enum.reduce(1..4, upload, fn _i, acc ->
          {:ok, rotated} = Media.rotate_upload(acc, 90)
          rotated
        end)

      assert {final.width, final.height} == {400, 200}
      assert final.revision == 4
    end

    test "refuses types where a rewrite would destroy the file" do
      # A GIF would lose its animation, an SVG its vector nature, a PDF is not an image.
      gif = write_tmp("GIF89a" <> <<0::size(64)>>)

      svg =
        write_tmp(~s(<svg xmlns="http://www.w3.org/2000/svg"><rect width="1" height="1"/></svg>))

      pdf = write_tmp(@pdf)

      for {path, name} <- [{gif, "a.gif"}, {svg, "b.svg"}, {pdf, "c.pdf"}] do
        {:ok, upload} = Media.store_file(path, %{filename: name})
        refute Media.rotatable?(upload)
        assert {:error, :not_rotatable} = Media.rotate_upload(upload, 90)
      end
    end

    test "rejects angles that are not quarter turns" do
      src = write_image(40, 20)
      {:ok, upload} = Media.store_file(src, %{filename: "x.png"})

      for angle <- [0, 45, 360, -90] do
        assert {:error, :invalid_angle} = Media.rotate_upload(upload, angle)
      end
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

  describe "resolve_variant/5 focal crop" do
    test "produces a distinct, correctly-sized variant when a focal point is given" do
      src = write_image(400, 200)
      {:ok, upload} = Media.store_file(src, %{filename: "wide.png"})

      assert {:ok, centered, "image/webp"} = Media.resolve_variant(upload.storage_key, 100, 100)

      assert {:ok, focal, "image/webp"} =
               Media.resolve_variant(upload.storage_key, 100, 100, 0.9, 0.5)

      # A focal crop is cached under a different key than the centered one …
      refute centered == focal
      # … and still yields exactly the requested box.
      {:ok, img} = Image.open(focal)
      assert Image.width(img) == 100
      assert Image.height(img) == 100
    end

    test "the same focal point is served from cache on repeat" do
      src = write_image(400, 200)
      {:ok, upload} = Media.store_file(src, %{filename: "wide.png"})

      assert {:ok, p1, _} = Media.resolve_variant(upload.storage_key, 120, 80, 0.2, 0.7)
      assert {:ok, ^p1, _} = Media.resolve_variant(upload.storage_key, 120, 80, 0.2, 0.7)
    end

    test "no focal point keeps the pre-focal cache key (existing caches stay valid)" do
      src = write_image(400, 200)
      {:ok, upload} = Media.store_file(src, %{filename: "wide.png"})

      assert {:ok, p1, _} = Media.resolve_variant(upload.storage_key, 100, 100)
      assert {:ok, ^p1, _} = Media.resolve_variant(upload.storage_key, 100, 100, nil, nil)
    end

    test "a focal point is ignored unless both dimensions are requested" do
      src = write_image(400, 200)
      {:ok, upload} = Media.store_file(src, %{filename: "wide.png"})

      # width-only variant: focal is irrelevant, so the cache key matches the plain call.
      assert {:ok, p1, _} = Media.resolve_variant(upload.storage_key, 100, nil)
      assert {:ok, ^p1, _} = Media.resolve_variant(upload.storage_key, 100, nil, 0.9, 0.1)
    end
  end
end
