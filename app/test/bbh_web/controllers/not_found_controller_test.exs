defmodule BbhWeb.NotFoundControllerTest do
  @moduledoc "The site-wide 404 path: catch-all route + BbhWeb.Redirector."
  use BbhWeb.ConnCase, async: true

  import Bbh.ContentFixtures

  alias Bbh.Redirects

  defp logged_paths, do: Redirects.list_not_found() |> Enum.map(& &1.path) |> Enum.sort()

  describe "a path no route claims" do
    test "renders the 404 page and logs the path", %{conn: conn} do
      conn =
        conn
        |> put_req_header("referer", "https://www.google.com/search?q=x")
        |> get("/verein/vorstand/kontakt/alt")

      assert response(conn, 404)

      assert [%{path: "/verein/vorstand/kontakt/alt", referrer: "www.google.com/search"}] =
               Redirects.list_not_found()
    end

    test "follows an editor rule, permanent or temporary, and counts the hit", %{conn: conn} do
      {:ok, rule} = Redirects.create_redirect(%{source_path: "/alt", target: "/kontakt"})

      {:ok, _} =
        Redirects.create_redirect(%{source_path: "/vorlaeufig", target: "/", permanent: false})

      assert redirected_to(get(conn, "/Alt/"), 301) == "/kontakt"
      assert redirected_to(get(conn, "/vorlaeufig"), 302) == "/"
      assert Redirects.get_redirect!(rule.id).hits == 1
      assert logged_paths() == []
    end

    test "follows a rule to an external URL", %{conn: conn} do
      {:ok, _} =
        Redirects.create_redirect(%{source_path: "/satzung", target: "https://example.org/s"})

      assert redirected_to(get(conn, "/satzung"), 301) == "https://example.org/s"
    end

    test "maps an old Hugo URL in one hop", %{conn: conn} do
      assert redirected_to(get(conn, "/datenschutzerklaerung/"), 301) == "/datenschutz"
    end

    test "does not log scanner probes or admin paths", %{conn: conn} do
      probes = [
        "/wp-login.php",
        "/.env",
        "/admin/gibt-es-nicht",
        "/kalender/geteilt/abc/x",
        "/id_rsa",
        "/ssl/server.key",
        "/_astro/pages/index.astro.mjs.map",
        "/Admin"
      ]

      for path <- probes do
        assert conn |> get(path) |> response(404)
      end

      assert logged_paths() == []
    end
  end

  describe "a route whose record is missing" do
    test "redirects an old article URL to the renamed slug", %{conn: conn} do
      article_fixture(slug: "kein-biwak", date_published: ~U[2020-06-01 10:00:00Z])

      assert redirected_to(get(conn, "/aktuell/2020/kein_biwak"), 301) ==
               "/aktuell/2020/kein-biwak"
    end

    test "a rule also covers a path under a matching route", %{conn: conn} do
      {:ok, _} =
        Redirects.create_redirect(%{source_path: "/verein/vorstand/kontakt", target: "/kontakt"})

      assert redirected_to(get(conn, "/verein/vorstand/kontakt"), 301) == "/kontakt"
    end

    test "a genuine miss is logged", %{conn: conn} do
      assert conn |> get("/aktuell/2026/gibt-es-nicht") |> response(404)
      assert logged_paths() == ["/aktuell/2026/gibt-es-nicht"]
    end

    test "an existing page is never redirected", %{conn: conn} do
      article = article_fixture()
      path = "/aktuell/#{article.year}/#{article.slug}"
      {:ok, _} = Redirects.create_redirect(%{source_path: path, target: "/kontakt"})

      assert conn |> get(path) |> html_response(200) =~ article.title
    end
  end
end
