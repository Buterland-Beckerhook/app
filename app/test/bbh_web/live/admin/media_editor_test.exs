defmodule BbhWeb.Admin.MediaEditorTest do
  # async: false — the rotation test overrides the global :bbh, :uploads_dir and writes files.
  use Bbh.DataCase

  import Bbh.ContentFixtures, only: [upload_fixture: 1]

  alias Bbh.Media
  alias BbhWeb.Admin.MediaEditor

  setup do
    tmp = Path.join(System.tmp_dir!(), "bbh_editor_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(tmp, "cache"))
    prev = Application.get_env(:bbh, :uploads_dir)
    prev_cache = Application.get_env(:bbh, :media_cache_dir)
    Application.put_env(:bbh, :uploads_dir, tmp)
    Application.put_env(:bbh, :media_cache_dir, Path.join(tmp, "cache"))

    on_exit(fn ->
      Application.put_env(:bbh, :uploads_dir, prev)
      Application.put_env(:bbh, :media_cache_dir, prev_cache)
      File.rm_rf(tmp)
    end)

    :ok
  end

  defp stored_image do
    {:ok, img} = Image.new(40, 20, color: [10, 120, 60])
    path = Path.join(System.tmp_dir!(), "src_#{System.unique_integer([:positive])}.png")
    {:ok, _} = Image.write(img, path)
    on_exit(fn -> File.rm(path) end)
    {:ok, upload} = Media.store_file(path, %{filename: "wide.png"})
    upload
  end

  describe "submit/2" do
    test "a plain save persists the metadata and closes the editor" do
      upload = upload_fixture(%{})

      assert {:close, saved, {:info, message}} =
               MediaEditor.submit(upload, %{
                 "upload" => %{"caption" => "Der Thron", "copyright" => "BBH e.V."}
               })

      assert saved.caption == "Der Thron"
      assert message =~ "gespeichert"
    end

    test "an empty folder select clears the folder instead of failing" do
      {:ok, folder} = Media.create_folder(%{"name" => "Presse"})
      upload = upload_fixture(folder_id: folder.id)

      assert {:close, saved, {:info, _}} =
               MediaEditor.submit(upload, %{"upload" => %{"folder_id" => ""}})

      assert is_nil(saved.folder_id)
    end

    test "a rotate submit saves the metadata *and* turns the image, keeping the editor open" do
      upload = stored_image()

      assert {:keep, rotated, {:info, message}} =
               MediaEditor.submit(upload, %{
                 "upload" => %{"caption" => "Vor dem Drehen getippt"},
                 "rotate" => "90"
               })

      assert message =~ "gedreht"
      assert {rotated.width, rotated.height} == {20, 40}
      # The point of routing rotation through the form: typed text is not lost.
      assert rotated.caption == "Vor dem Drehen getippt"
    end

    test "a rotation that cannot be done still keeps the saved metadata" do
      pdf = Path.join(System.tmp_dir!(), "doc_#{System.unique_integer([:positive])}.pdf")
      File.write!(pdf, "%PDF-1.4\n%\xE2\xE3\xCF\xD3\ntrailer<</Root 1 0 R>>\n%%EOF")
      on_exit(fn -> File.rm(pdf) end)
      {:ok, upload} = Media.store_file(pdf, %{filename: "satzung.pdf"})

      assert {:keep, kept, {:error, message}} =
               MediaEditor.submit(upload, %{
                 "upload" => %{"title" => "Satzung 2026"},
                 "rotate" => "90"
               })

      assert message =~ "nicht gedreht werden"
      # The editor stays open on what is actually stored now, not on stale values.
      assert kept.title == "Satzung 2026"
      assert Media.get_upload!(upload.id).title == "Satzung 2026"
    end

    test "a bogus angle is refused without touching the file" do
      upload = stored_image()

      for angle <- ["45", "abc", ""] do
        assert {:keep, _kept, {:error, _}} =
                 MediaEditor.submit(upload, %{"upload" => %{}, "rotate" => angle})
      end

      assert Media.get_upload!(upload.id).revision == 0
    end
  end
end
