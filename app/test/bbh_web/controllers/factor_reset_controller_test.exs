defmodule BbhWeb.FactorResetControllerTest do
  use BbhWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Bbh.AccountsFixtures

  alias Bbh.Accounts

  # A user whose factors an admin reset, now back from a magic-link login.
  setup %{conn: conn} do
    user = user_fixture()
    passkey_fixture(user)
    {:ok, {code, _}} = Accounts.reset_second_factors(user)
    %{user: user, code: code, conn: log_in_user(conn, user, auth_method: "magic_link")}
  end

  test "mailbox access alone cannot enroll a new factor", %{conn: conn} do
    for path <- [
          ~p"/users/security",
          ~p"/admin/einstellungen/passkeys",
          ~p"/admin/einstellungen/2fa"
        ] do
      assert {:error, {:redirect, %{to: "/users/reset-code"}}} = live(conn, path)
    end

    # The strong-auth areas funnel there as well (via the enrollment page).
    assert {:error, {:redirect, %{to: "/users/security"}}} = live(conn, ~p"/admin/artikel")
  end

  test "a wrong code is rejected and logged", %{conn: conn, user: user} do
    conn = post(conn, ~p"/users/reset-code", %{"reset" => %{"code" => "AAAA-AAAA"}})

    assert html_response(conn, 200) =~ "Ungültiger oder abgelaufener Code"
    refute get_session(conn, :factor_reset_verified)

    assert [%{event: "factor_reset_failed"}] =
             Bbh.Repo.all_by(Bbh.Accounts.AuthEvent,
               user_id: user.id,
               event: "factor_reset_failed"
             )
  end

  test "the right code unlocks enrollment for this session", %{conn: conn, code: code, user: user} do
    assert html_response(get(conn, ~p"/users/reset-code"), 200) =~ "Zugang wiederherstellen"

    conn = post(conn, ~p"/users/reset-code", %{"reset" => %{"code" => String.downcase(code)}})
    assert redirected_to(conn) == ~p"/users/security"

    conn = recycle(conn)
    assert {:ok, _lv, html} = live(conn, ~p"/users/security")
    assert html =~ "Passkey einrichten"

    {:ok, lv, html} = live(conn, ~p"/admin/einstellungen/2fa")
    [_, b32] = Regex.run(~r/id="totp-secret"[^>]*>([A-Z2-7]+)</, html)
    code = b32 |> Base.decode32!(padding: false) |> NimbleTOTP.verification_code()

    html = lv |> element("form[phx-submit=enable]") |> render_submit(%{"code" => code})

    assert html =~ "Zwei-Faktor ist für dein Konto aktiviert"

    refute Accounts.factor_reset_pending?(user)
  end

  test "without a pending reset the page is not needed" do
    conn = log_in_user(build_conn(), user_fixture(), auth_method: "magic_link")
    assert redirected_to(get(conn, ~p"/users/reset-code")) == ~p"/users/security"
  end
end
