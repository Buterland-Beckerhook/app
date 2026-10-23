defmodule BbhWeb.Admin.RedirectLiveTest do
  use BbhWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Bbh.Redirects

  setup :register_and_log_in_admin

  describe "Index" do
    test "lists rules and the 404 log", %{conn: conn} do
      {:ok, rule} = Redirects.create_redirect(%{source_path: "/alt", target: "/kontakt"})
      Redirects.record_not_found("/verein/ehrenmal")
      [entry] = Redirects.list_not_found()

      {:ok, lv, _html} = live(conn, ~p"/admin/weiterleitungen")

      assert has_element?(lv, "#redirect-#{rule.id}", "/kontakt")
      assert has_element?(lv, "#not-found-#{entry.id}", "/verein/ehrenmal")
    end

    test "checks a path against rules and old URLs", %{conn: conn} do
      {:ok, _} = Redirects.create_redirect(%{source_path: "/alt", target: "/kontakt"})
      {:ok, lv, _html} = live(conn, ~p"/admin/weiterleitungen")

      lv |> form("#check-form", check: %{path: "/ALT/"}) |> render_submit()
      assert has_element?(lv, "#check-result", "/kontakt")

      lv |> form("#check-form", check: %{path: "/datenschutzerklaerung"}) |> render_submit()
      assert has_element?(lv, "#check-result", "alte Adresse")

      lv |> form("#check-form", check: %{path: "/nirgends"}) |> render_submit()
      assert has_element?(lv, "#check-result", "keine Weiterleitung")
    end

    test "dismisses a 404-log entry", %{conn: conn} do
      Redirects.record_not_found("/tippfehler")
      [entry] = Redirects.list_not_found()
      {:ok, lv, _html} = live(conn, ~p"/admin/weiterleitungen")

      lv |> element("#dismiss-#{entry.id}") |> render_click()

      refute has_element?(lv, "#not-found-#{entry.id}")
      assert Redirects.list_not_found() == []
    end
  end

  describe "Form" do
    test "creates a rule prefilled from the 404 log and clears that entry", %{conn: conn} do
      Redirects.record_not_found("/verein/ehrenmal")
      {:ok, lv, html} = live(conn, ~p"/admin/weiterleitungen/neu?von=/verein/ehrenmal")

      assert html =~ "/verein/ehrenmal"

      {:ok, _lv, html} =
        lv
        |> form("#redirect-form", redirect: %{target: "/verein/ueber-uns/ehrenmal"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/weiterleitungen")

      assert html =~ "Weiterleitung erstellt"
      assert [%{source_path: "/verein/ehrenmal"}] = Redirects.list_redirects()
      assert Redirects.list_not_found() == []
    end

    test "validate shows a loop error", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/weiterleitungen/neu")

      html =
        lv
        |> form("#redirect-form", redirect: %{source_path: "/a", target: "/a/"})
        |> render_change()

      assert html =~ "würde wieder auf diese Weiterleitung zeigen"
    end

    test "edits and deletes a rule", %{conn: conn} do
      {:ok, rule} = Redirects.create_redirect(%{source_path: "/alt", target: "/kontakt"})
      {:ok, lv, _html} = live(conn, ~p"/admin/weiterleitungen/#{rule.id}/bearbeiten")

      {:ok, _lv, _html} =
        lv
        |> form("#redirect-form", redirect: %{target: "/termine"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/weiterleitungen")

      assert Redirects.get_redirect!(rule.id).target == "/termine"

      {:ok, lv, _html} = live(conn, ~p"/admin/weiterleitungen/#{rule.id}/bearbeiten")

      {:ok, _lv, html} =
        lv
        |> form("form[phx-submit=delete]", confirm: "/alt")
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/weiterleitungen")

      assert html =~ "Weiterleitung gelöscht"
      assert Redirects.list_redirects() == []
    end
  end
end
