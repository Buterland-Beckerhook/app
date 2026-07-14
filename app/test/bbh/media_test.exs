defmodule Bbh.MediaTest do
  # async: false — overrides the global :bbh, :uploads_dir and writes real files.
  use Bbh.DataCase

  alias Bbh.Media
  alias Bbh.Media.Upload

  import Bbh.ContentFixtures, only: [upload_fixture: 1]

  # 1×1 transparent PNG.
  @png Base.decode64!(
         "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
       )

  setup do
    tmp = Path.join(System.tmp_dir!(), "bbh_media_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    prev = Application.get_env(:bbh, :uploads_dir)
    Application.put_env(:bbh, :uploads_dir, tmp)

    on_exit(fn ->
      Application.put_env(:bbh, :uploads_dir, prev)
      File.rm_rf(tmp)
    end)

    {:ok, tmp: tmp}
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
  end
end
