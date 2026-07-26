defmodule BbhWeb.ArticleControllerTest do
  use BbhWeb.ConnCase, async: true

  import Bbh.ContentFixtures

  describe "GET /aktuell" do
    test "lists published articles and hides throne-only entries", %{conn: conn} do
      shown = article_fixture(title: "Öffentlicher Bericht")
      hidden = article_fixture(title: "Nur Thron", no_article: true)

      html = conn |> get(~p"/aktuell") |> html_response(200)
      assert html =~ shown.title
      refute html =~ hidden.title
    end
  end

  describe "GET /aktuell/:year/:slug" do
    test "renders a published article", %{conn: conn} do
      article = article_fixture(title: "Jubiläum")
      html = conn |> get(~p"/aktuell/#{article.year}/#{article.slug}") |> html_response(200)
      assert html =~ "Jubiläum"
    end

    test "returns 404 for an unknown article", %{conn: conn} do
      conn = get(conn, ~p"/aktuell/2026/gibt-es-nicht")
      assert response(conn, 404)
    end

    test "hides the admin edit link from anonymous visitors", %{conn: conn} do
      article = article_fixture()
      html = conn |> get(~p"/aktuell/#{article.year}/#{article.slug}") |> html_response(200)
      refute html =~ "/bearbeiten"
    end

    test "returns 404 for a draft article for anonymous visitors", %{conn: conn} do
      article = article_fixture(status: "draft")
      assert conn |> get(~p"/aktuell/#{article.year}/#{article.slug}") |> response(404)
    end

    test "returns 404 for a non-numeric year", %{conn: conn} do
      conn = get(conn, ~p"/aktuell/abcd/irgendwas")
      assert response(conn, 404)
    end

    test "falls back to the club logo when the article has no images", %{conn: conn} do
      article = article_fixture()
      html = conn |> get(~p"/aktuell/#{article.year}/#{article.slug}") |> html_response(200)
      # The logo URL is on every page (og:image + nav), so assert the hero
      # fallback's distinctive alt instead (the nav logo uses alt="").
      assert html =~ ~s(alt="Buterland-Beckerhook")
    end

    test "renders a real hero image, not the logo, when the article has one", %{conn: conn} do
      article = article_fixture()
      {:ok, _} = Bbh.Content.add_article_image(article, upload_fixture().id)

      html = conn |> get(~p"/aktuell/#{article.year}/#{article.slug}") |> html_response(200)
      assert html =~ "/media/"
      refute html =~ ~s(alt="Buterland-Beckerhook")
    end

    test "renders gallery images as lightbox triggers", %{conn: conn} do
      article = article_fixture()
      {:ok, _} = Bbh.Content.add_article_image(article, upload_fixture().id)
      {:ok, _} = Bbh.Content.add_article_image(article, upload_fixture().id)

      html = conn |> get(~p"/aktuell/#{article.year}/#{article.slug}") |> html_response(200)
      # The hero is excluded, leaving at least one gallery image with a lightbox trigger.
      assert html =~ "data-lightbox-src"
    end

    test "shows the hero's caption and copyright from the media library", %{conn: conn} do
      article = article_fixture()

      upload =
        upload_fixture(%{caption: "Der Thron 2025", copyright: "Buterland-Beckerhook e.V."})

      {:ok, _} = Bbh.Content.add_article_image(article, upload.id)

      credit = conn |> get(~p"/aktuell/#{article.year}/#{article.slug}") |> credit_text()

      assert credit =~ "Der Thron 2025"
      assert credit =~ "© Buterland-Beckerhook e.V."
    end

    test "an article can hide the caption but keeps the copyright", %{conn: conn} do
      article = article_fixture()
      upload = upload_fixture(%{caption: "Der Thron 2025", copyright: "BBH e.V."})
      {:ok, image} = Bbh.Content.add_article_image(article, upload.id)
      {:ok, _} = Bbh.Content.update_article_image(image, %{show_caption: false})

      conn = get(conn, ~p"/aktuell/#{article.year}/#{article.slug}")

      refute credit_text(conn) =~ "Der Thron 2025"
      assert credit_text(conn) =~ "© BBH e.V."
      # Hiding the caption is a layout decision; the alt text stays for screen readers.
      assert html_response(conn, 200) =~ ~s(alt="Der Thron 2025")
    end

    test "gallery thumbnails stay bare — their caption rides along for the lightbox", ctx do
      article = article_fixture()
      {:ok, _hero} = Bbh.Content.add_article_image(article, upload_fixture().id)

      second = upload_fixture(%{caption: "Fahnenschwenken", copyright: "BBH e.V."})
      {:ok, _} = Bbh.Content.add_article_image(article, second.id)

      html = ctx.conn |> get(~p"/aktuell/#{article.year}/#{article.slug}") |> html_response(200)

      assert html =~ ~s(data-lightbox-caption="Fahnenschwenken")
      assert html =~ ~s(data-lightbox-copyright="© BBH e.V.")
    end

    test "images appear in the editor's sort order", %{conn: conn} do
      article = article_fixture()
      {:ok, hero} = Bbh.Content.add_article_image(article, upload_fixture().id)

      {:ok, second} =
        Bbh.Content.add_article_image(article, upload_fixture(%{caption: "Zwei"}).id)

      {:ok, third} = Bbh.Content.add_article_image(article, upload_fixture(%{caption: "Drei"}).id)

      # Put the last image second.
      {:ok, _} = Bbh.Content.update_article_image(hero, %{sort: 0})
      {:ok, _} = Bbh.Content.update_article_image(third, %{sort: 1})
      {:ok, _} = Bbh.Content.update_article_image(second, %{sort: 2})

      html = conn |> get(~p"/aktuell/#{article.year}/#{article.slug}") |> html_response(200)

      # Both must actually be present: :binary.match/2 returns :nomatch, and an atom
      # sorts before a tuple, so comparing the raw results would pass vacuously.
      assert {drei, _} = :binary.match(html, "Drei")
      assert {zwei, _} = :binary.match(html, "Zwei")
      assert drei < zwei
    end
  end

  describe "admin edit affordance" do
    setup :register_and_log_in_admin

    test "shows an edit link to the article form for editors", %{conn: conn} do
      article = article_fixture(title: "Redigierbar")
      html = conn |> get(~p"/aktuell/#{article.year}/#{article.slug}") |> html_response(200)
      assert html =~ ~p"/admin/artikel/#{article.id}/bearbeiten"
    end

    test "previews a draft article with a banner for editors", %{conn: conn} do
      article = article_fixture(title: "Noch Entwurf", status: "draft")
      html = conn |> get(~p"/aktuell/#{article.year}/#{article.slug}") |> html_response(200)
      assert html =~ "Noch Entwurf"
      assert html =~ "Vorschau"
    end
  end

  describe "GET /aktuell (listing)" do
    test "uses the logo fallback on cards for image-less articles", %{conn: conn} do
      article_fixture(title: "Ohne Bild")
      html = conn |> get(~p"/aktuell") |> html_response(200)
      # Card fallback is the only element with this alt (nav logo uses alt="").
      assert html =~ ~s(alt="Buterland-Beckerhook")
    end
  end

  # The visible caption/copyright line, as text — asserting against raw HTML would also
  # match the alt attribute, which is a different thing.
  defp credit_text(conn) do
    conn
    |> html_response(200)
    |> LazyHTML.from_document()
    |> LazyHTML.query("figcaption")
    |> LazyHTML.text()
  end
end
