defmodule BbhWeb.UserLive.SecuritySetupTest do
  use BbhWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Bbh.AccountsFixtures

  alias Bbh.Accounts

  setup :register_and_log_in_user

  test "shows both cards when the user has no passkey and no 2FA", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/users/security")

    assert html =~ "Konto absichern"
    assert html =~ "Passkey einrichten"
    assert html =~ "Zwei-Faktor"
    assert html =~ ~p"/admin/einstellungen/passkeys"
    assert html =~ ~p"/admin/einstellungen/2fa"
    # Skippable — the explicit skip link is present.
    assert html =~ "Später erinnern"
  end

  test "hides the passkey card once a passkey exists", %{conn: conn, user: user} do
    passkey_fixture(user)
    {:ok, _lv, html} = live(conn, ~p"/users/security")

    refute html =~ "Passkey einrichten"
    assert html =~ "Zwei-Faktor"
  end

  test "redirects to the admin area when nothing is missing", %{conn: conn, user: user} do
    passkey_fixture(user)
    {:ok, _user} = Accounts.enable_totp(user, Accounts.generate_totp_secret())

    assert {:error, {:live_redirect, %{to: "/admin"}}} = live(conn, ~p"/users/security")
  end

  test "requires an authenticated user" do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} =
             live(build_conn(), ~p"/users/security")
  end
end
