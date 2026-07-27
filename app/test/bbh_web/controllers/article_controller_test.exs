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

    test "hides drafts and shows the login link for anonymous visitors", %{conn: conn} do
      draft = article_fixture(title: "Geheimer Entwurf", status: "draft")

      html = conn |> get(~p"/aktuell") |> html_response(200)
      refute html =~ draft.title
      assert html =~ ~p"/users/log-in"
      assert html =~ "Anmelden"
      refute html =~ ~p"/admin"
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

    test "renders a real article image, not the logo, when the article has one", %{conn: conn} do
      article = article_fixture()
      set_article_image(article, upload_fixture())

      html = conn |> get(~p"/aktuell/#{article.year}/#{article.slug}") |> html_response(200)
      assert html =~ "/media/"
      refute html =~ ~s(alt="Buterland-Beckerhook")
    end

    test "renders gallery block images as lightbox triggers", %{conn: conn} do
      article = article_fixture()
      gallery_block_fixture(article, [upload_fixture(), upload_fixture()])

      html = conn |> get(~p"/aktuell/#{article.year}/#{article.slug}") |> html_response(200)
      assert html =~ "data-lightbox-src"
    end

    test "shows the article image's caption and copyright from the media library", %{conn: conn} do
      article = article_fixture()

      upload =
        upload_fixture(%{caption: "Der Thron 2025", copyright: "Buterland-Beckerhook e.V."})

      set_article_image(article, upload)

      credit = conn |> get(~p"/aktuell/#{article.year}/#{article.slug}") |> credit_text()

      assert credit =~ "Der Thron 2025"
      assert credit =~ "© Buterland-Beckerhook e.V."
    end

    test "gallery thumbnails stay bare — their caption rides along for the lightbox", ctx do
      article = article_fixture()
      second = upload_fixture(%{caption: "Fahnenschwenken", copyright: "BBH e.V."})
      gallery_block_fixture(article, [second])

      html = ctx.conn |> get(~p"/aktuell/#{article.year}/#{article.slug}") |> html_response(200)

      assert html =~ ~s(data-lightbox-caption="Fahnenschwenken")
      assert html =~ ~s(data-lightbox-copyright="© BBH e.V.")
    end

    test "gallery images appear in the editor's sort order", %{conn: conn} do
      article = article_fixture()
      second = upload_fixture(%{caption: "Zwei"})
      third = upload_fixture(%{caption: "Drei"})

      # Added third-then-second, so "Drei" must render before "Zwei".
      gallery_block_fixture(article, [third, second])

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

    test "lists drafts with a badge and links the footer to the admin area", %{conn: conn} do
      draft = article_fixture(title: "Entwurf im Listing", status: "draft")

      html = conn |> get(~p"/aktuell") |> html_response(200)
      assert html =~ draft.title
      assert html =~ "Entwurf"
      assert html =~ ~p"/admin"
      assert html =~ "Administration"
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
