defmodule BbhWeb.NotFoundHTMLTest do
  use BbhWeb.ConnCase, async: true

  import Bbh.AccountsFixtures

  doctest BbhWeb.NotFoundHTML

  describe "the 404 page" do
    test "renders in the site layout with search and section links", %{conn: conn} do
      conn = get(conn, "/aktuell/2019/pokal_und-preisschiessen-alt")
      html = html_response(conn, 404)
      doc = LazyHTML.from_document(html)

      assert html =~ "Seite nicht gefunden"
      assert html =~ "/aktuell/2019/pokal_und-preisschiessen-alt"

      # Site chrome (header logo) is there, not a bare "Not Found".
      assert doc |> LazyHTML.query("header img") |> LazyHTML.attribute("src") ==
               ["/images/logo.svg"]

      [query] = doc |> LazyHTML.query("#not-found-q") |> LazyHTML.attribute("value")
      assert query == "pokal und preisschiessen alt"

      hrefs = doc |> LazyHTML.query("#not-found-links a") |> LazyHTML.attribute("href")
      assert hrefs == ["/", "/aktuell", "/termine", "/verein"]
    end

    test "the catch-all route sends the security headers and a CSP", %{conn: conn} do
      conn = get(conn, "/gibt/es/nicht")

      assert html_response(conn, 404) =~ "Seite nicht gefunden"
      assert [_] = get_resp_header(conn, "content-security-policy")
      assert [_] = get_resp_header(conn, "x-content-type-options")
    end

    test "a missing record behind a real route renders the same page", %{conn: conn} do
      assert conn |> get("/termine/2023/gibt-es-nicht") |> html_response(404) =~
               "Seite nicht gefunden"
    end

    test "knows the logged-in user on the catch-all route", %{conn: conn} do
      conn = conn |> log_in_user(admin_user_fixture()) |> get("/gibt/es/nicht")
      html = html_response(conn, 404)

      # The footer offers the admin link only to a logged-in user.
      assert html =~ "Administration"
    end
  end
end
