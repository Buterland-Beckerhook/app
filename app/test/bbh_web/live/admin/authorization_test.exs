defmodule BbhWeb.Admin.AuthorizationTest do
  use BbhWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Bbh.AccountsFixtures

  @admin_routes [
    "/admin",
    "/admin/artikel",
    "/admin/artikel/neu",
    "/admin/termine",
    "/admin/termine/neu",
    "/admin/orte",
    "/admin/orte/neu",
    "/admin/personen",
    "/admin/personen/neu",
    "/admin/medien",
    "/admin/seiten",
    "/admin/seiten/neu",
    "/admin/benutzer",
    "/admin/website",
    "/admin/push",
    "/admin/bankleitzahlen",
    "/admin/weiterleitungen",
    "/admin/weiterleitungen/neu"
  ]

  describe "unauthenticated access" do
    for route <- @admin_routes do
      test "redirects #{route} to the login page", %{conn: conn} do
        assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, unquote(route))
      end
    end
  end

  describe "role-based access to user management" do
    test "an editor is redirected away from /admin/benutzer", %{conn: conn} do
      editor = user_fixture()
      conn = log_in_user(conn, editor)

      assert {:error, {:redirect, %{to: "/admin", flash: %{"error" => msg}}}} =
               live(conn, ~p"/admin/benutzer")

      assert msg =~ "Administratoren"
    end

    test "an admin can open /admin/benutzer", %{conn: conn} do
      admin = admin_user_fixture()
      conn = log_in_user(conn, admin, auth_method: "passkey")

      {:ok, _lv, html} = live(conn, ~p"/admin/benutzer")
      assert html =~ "Benutzer"
    end

    test "an admin with a magic-link-only session sets up a second factor first", %{
      conn: conn
    } do
      conn = log_in_user(conn, admin_user_fixture(), auth_method: "magic_link")

      assert {:error, {:redirect, %{to: "/users/security", flash: %{"error" => msg}}}} =
               live(conn, ~p"/admin/benutzer")

      assert msg =~ "Passkey"
    end

    test "an admin who has TOTP is asked to log in again with it", %{conn: conn} do
      {:ok, admin} =
        Bbh.Accounts.enable_totp(admin_user_fixture(), Bbh.Accounts.generate_totp_secret())

      conn = log_in_user(conn, admin, auth_method: "magic_link")

      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin/benutzer")
    end

    test "an editor can open the general admin area", %{conn: conn} do
      editor = user_fixture()
      conn = log_in_user(conn, editor)

      {:ok, _lv, html} = live(conn, ~p"/admin/artikel")
      assert html =~ "Artikel"
    end
  end

  describe "admin-only site settings, push and redirects" do
    for route <- ["/admin/website", "/admin/push", "/admin/weiterleitungen"] do
      test "an editor is redirected away from #{route}", %{conn: conn} do
        editor = user_fixture()
        conn = log_in_user(conn, editor)

        assert {:error, {:redirect, %{to: "/admin"}}} = live(conn, unquote(route))
      end

      test "an admin can open #{route}", %{conn: conn} do
        admin = admin_user_fixture()
        conn = log_in_user(conn, admin, auth_method: "magic_link_totp")

        assert {:ok, _lv, _html} = live(conn, unquote(route))
      end
    end
  end

  describe "plain (magic-link) session" do
    setup %{conn: conn} do
      admin = admin_user_fixture()
      %{conn: log_in_user(conn, admin, auth_method: "magic_link")}
    end

    for route <- [
          "/admin/artikel",
          "/admin/medien",
          "/admin/seiten",
          "/admin/benutzer",
          "/admin/website",
          "/admin/weiterleitungen"
        ] do
      test "is sent to set up a second factor from #{route}", %{conn: conn} do
        assert {:error, {:redirect, %{to: "/users/security", flash: %{"error" => msg}}}} =
                 live(conn, unquote(route))

        assert msg =~ "Passkey oder Zwei-Faktor-Code"
      end
    end

    test "is sent to log in again when a second factor exists" do
      admin = admin_user_fixture()
      passkey_fixture(admin)
      conn = log_in_user(build_conn(), admin, auth_method: "magic_link")

      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin/artikel")
    end

    test "still reaches the dashboard and Termine", %{conn: conn} do
      assert {:ok, _lv, _html} = live(conn, ~p"/admin")
      assert {:ok, _lv, _html} = live(conn, ~p"/admin/termine")
      assert {:ok, _lv, _html} = live(conn, ~p"/admin/termine/teilen")
    end
  end

  describe "role Nur Postfach" do
    setup %{conn: conn} do
      user = user_fixture()
      {:ok, user} = Bbh.Accounts.update_user_role(user, "tickets")
      %{conn: log_in_user(conn, user)}
    end

    test "opens the dashboard but no content or Termine", %{conn: conn} do
      assert {:ok, _lv, html} = live(conn, ~p"/admin")
      refute html =~ ~s|href="/admin/termine"|
      refute html =~ ~s|href="/admin/artikel"|

      for route <- ["/admin/termine", "/admin/termine/teilen", "/admin/artikel"] do
        assert {:error, {:redirect, _}} = live(conn, route)
      end
    end
  end
end
