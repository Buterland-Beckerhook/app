defmodule BbhWeb.MediaControllerTest do
  # async: false — overrides the global :bbh, :uploads_dir and writes real files.
  use BbhWeb.ConnCase

  alias Bbh.Media

  @png Base.decode64!(
         "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
       )

  setup do
    tmp = Path.join(System.tmp_dir!(), "bbh_media_ctrl_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    prev = Application.get_env(:bbh, :uploads_dir)
    Application.put_env(:bbh, :uploads_dir, tmp)

    on_exit(fn ->
      Application.put_env(:bbh, :uploads_dir, prev)
      File.rm_rf(tmp)
    end)

    {:ok, tmp: tmp}
  end

  defp store(bytes, filename) do
    src = Path.join(System.tmp_dir!(), "src_#{System.unique_integer([:positive])}")
    File.write!(src, bytes)
    on_exit(fn -> File.rm(src) end)
    {:ok, upload} = Media.store_file(src, %{filename: filename})
    upload
  end

  test "serves a stored image with its content type", %{conn: conn} do
    upload = store(@png, "bild.png")
    conn = get(conn, ~p"/media/#{upload.storage_key}")

    assert response(conn, 200)
    assert response_content_type(conn, :png) =~ "image/png"
  end

  test "serves SVG as an attachment (never inline)", %{conn: conn} do
    upload = store(~s(<svg xmlns="http://www.w3.org/2000/svg"></svg>), "logo.svg")
    conn = get(conn, ~p"/media/#{upload.storage_key}")

    assert response(conn, 200)
    assert get_resp_header(conn, "content-disposition") == ["attachment"]
  end

  describe "cache-control" do
    defp cache_control(conn, path),
      do: conn |> get(path) |> get_resp_header("cache-control")

    test "a variant at the current revision is immutable for a year", %{conn: conn} do
      upload = store(@png, "bild.png")

      assert cache_control(conn, "/media/#{upload.storage_key}?w=10&h=10") ==
               ["public, max-age=31536000, immutable"]
    end

    test "after a rotation, only the URL with the new revision is immutable", %{conn: conn} do
      {:ok, upload} = @png |> store("bild.png") |> Media.rotate_upload(90)
      assert upload.revision == 1

      assert cache_control(conn, "/media/#{upload.storage_key}?w=10&v=1") ==
               ["public, max-age=31536000, immutable"]

      # The pre-rotation URL now serves the rotated picture — it must not be pinned.
      assert cache_control(conn, "/media/#{upload.storage_key}?w=10") ==
               ["public, max-age=86400"]

      assert cache_control(conn, "/media/#{upload.storage_key}?w=10&v=junk") ==
               ["public, max-age=86400"]
    end

    test "an original is cached for a day — bare links to it never change", %{conn: conn} do
      upload = store(@png, "bild.png")

      assert cache_control(conn, "/media/#{upload.storage_key}") == ["public, max-age=86400"]
    end

    test "the original standing in for a failed variant is cached briefly", ctx do
      upload = store(@png, "bild.png")
      # Corrupt the stored file: a variant can no longer be generated from it.
      File.write!(Path.join(ctx.tmp, upload.storage_key), "not a png")

      conn = get(ctx.conn, "/media/#{upload.storage_key}?w=10")

      assert response(conn, 200)
      assert response_content_type(conn, :png) =~ "image/png"
      assert get_resp_header(conn, "cache-control") == ["public, max-age=300"]
    end
  end

  test "returns 404 for an unknown key", %{conn: conn} do
    assert conn |> get(~p"/media/2026/does-not-exist.png") |> response(404)
  end

  test "rejects path traversal", %{conn: conn} do
    assert conn |> get("/media/../../etc/passwd") |> response(404)
  end
end
