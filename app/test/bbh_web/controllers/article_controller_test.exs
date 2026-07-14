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

    test "returns 404 for a non-numeric year", %{conn: conn} do
      conn = get(conn, ~p"/aktuell/abcd/irgendwas")
      assert response(conn, 404)
    end

    test "falls back to the club logo when the article has no images", %{conn: conn} do
      article = article_fixture()
      html = conn |> get(~p"/aktuell/#{article.year}/#{article.slug}") |> html_response(200)
      assert html =~ "/images/logo.svg"
    end

    test "renders gallery images as lightbox triggers", %{conn: conn} do
      article = article_fixture()
      {:ok, _} = Bbh.Content.add_article_image(article, upload_fixture().id)
      {:ok, _} = Bbh.Content.add_article_image(article, upload_fixture().id)

      html = conn |> get(~p"/aktuell/#{article.year}/#{article.slug}") |> html_response(200)
      # The hero is excluded, leaving at least one gallery image with a lightbox trigger.
      assert html =~ "data-lightbox-src"
    end
  end

  describe "GET /aktuell (listing)" do
    test "uses the logo fallback on cards for image-less articles", %{conn: conn} do
      article_fixture(title: "Ohne Bild")
      html = conn |> get(~p"/aktuell") |> html_response(200)
      assert html =~ "/images/logo.svg"
    end
  end
end
