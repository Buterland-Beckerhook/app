defmodule BbhWeb.Admin.ArticleImageUploadTest do
  # async: false — overrides the global :uploads_dir and writes files.
  use BbhWeb.ConnCase

  import Phoenix.LiveViewTest
  import Bbh.ContentFixtures

  alias Bbh.Content

  # 1×1 transparent PNG.
  @png Base.decode64!(
         "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
       )

  setup :register_and_log_in_admin

  setup do
    tmp = Path.join(System.tmp_dir!(), "bbh_article_upload_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    prev = Application.get_env(:bbh, :uploads_dir)
    Application.put_env(:bbh, :uploads_dir, tmp)

    on_exit(fn ->
      Application.put_env(:bbh, :uploads_dir, prev)
      File.rm_rf(tmp)
    end)

    :ok
  end

  test "uploading an image stores it and attaches it to the article", %{conn: conn} do
    article = article_fixture()
    {:ok, lv, _html} = live(conn, ~p"/admin/artikel/#{article.id}/bearbeiten")
    render_async(lv)

    file =
      file_input(lv, "#article-image-upload", :image, [
        %{name: "wappen.png", content: @png, type: "image/png"}
      ])

    assert render_upload(file, "wappen.png") =~ "wappen.png"

    html = lv |> element("#article-image-upload") |> render_submit()

    assert html =~ "hochgeladen und hinzugefügt"
    assert [%{}] = Content.list_article_images(article.id)
  end

  test "rejects bytes that are not a real image", %{conn: conn} do
    article = article_fixture()
    {:ok, lv, _html} = live(conn, ~p"/admin/artikel/#{article.id}/bearbeiten")
    render_async(lv)

    file =
      file_input(lv, "#article-image-upload", :image, [
        %{name: "fake.png", content: "definitely not an image", type: "image/png"}
      ])

    render_upload(file, "fake.png")
    html = lv |> element("#article-image-upload") |> render_submit()

    assert html =~ "konnten nicht hochgeladen werden"
    assert Content.list_article_images(article.id) == []
  end
end
