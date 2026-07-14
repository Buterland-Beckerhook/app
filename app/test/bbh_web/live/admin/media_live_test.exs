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

      assert html =~ "nicht als gültiges Bild erkannt"
      assert Media.list_uploads() == []
    end
  end
end
