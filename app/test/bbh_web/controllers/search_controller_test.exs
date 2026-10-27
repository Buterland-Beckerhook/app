defmodule BbhWeb.SearchControllerTest do
  use BbhWeb.ConnCase, async: true

  import Bbh.ContentFixtures

  describe "GET /suche" do
    test "shows a hint and no query when q is blank", %{conn: conn} do
      html = conn |> get(~p"/suche") |> html_response(200)
      assert html =~ "Suche"
      assert html =~ "Geben Sie einen Suchbegriff ein"
    end

    test "lists matching results with a highlighted snippet", %{conn: conn} do
      article_fixture(%{
        title: "Preisschießen",
        slug: "preisschiessen",
        body: "<p>Das Preisschießen findet im Herbst statt.</p>"
      })

      Bbh.Search.reindex_all()

      html = conn |> get(~p"/suche?#{[q: "Preisschießen"]}") |> html_response(200)

      assert html =~ "Preisschießen"
      assert html =~ ~s(/aktuell/)
      # The snippet's sentinel markers must be rendered as <mark>, not leaked raw.
      assert html =~ "<mark>"
      refute html =~ "@@M@@"
    end

    test "?tag= lists the articles carrying that tag, case-insensitively", %{conn: conn} do
      article_fixture(%{title: "Mit Schlagwort", tags: ["Jugend", "Kinder"]})
      article_fixture(%{title: "Ohne Schlagwort", tags: ["Vorstand"]})
      article_fixture(%{title: "Entwurf mit Schlagwort", tags: ["Jugend"], status: "draft"})

      html = conn |> get(~p"/suche?#{[tag: "jugend"]}") |> html_response(200)

      assert html =~ "Mit Schlagwort"
      refute html =~ "Ohne Schlagwort"
      refute html =~ "Entwurf mit Schlagwort"
      assert html =~ "1 Artikel mit dem Schlagwort"
      # The card's own tags link on to their listings.
      assert html =~ ~s(href="/suche?tag=Kinder")
    end

    test "reports no results for a non-matching query", %{conn: conn} do
      html = conn |> get(~p"/suche?#{[q: "zzzznichtvorhanden"]}") |> html_response(200)
      assert html =~ "Keine Ergebnisse"
    end
  end
end
