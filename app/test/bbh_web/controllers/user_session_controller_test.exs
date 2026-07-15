defmodule BbhWeb.UserSessionControllerTest do
  use BbhWeb.ConnCase, async: true

  import Bbh.AccountsFixtures
  alias Bbh.Accounts

  setup do
    %{unconfirmed_user: unconfirmed_user_fixture(), user: user_fixture()}
  end

  describe "POST /users/log-in - magic link" do
    test "logs the user in", %{conn: conn, user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => token}
        })

      assert get_session(conn, :user_token)
      # No passkey/2FA yet → nudged to the enrollment page (skippable).
      assert redirected_to(conn) == ~p"/users/security"

      # Now do a logged in request and assert on the admin menu
      conn = get(conn, ~p"/admin")
      response = html_response(conn, 200)
      assert response =~ user.email
      assert response =~ ~p"/users/log-out"
    end

    test "sends a fully enrolled user straight to the admin area", %{conn: conn, user: user} do
      passkey_fixture(user)
      {:ok, user} = Accounts.enable_totp(user, Accounts.generate_totp_secret())
      {token, _hashed_token} = generate_user_magic_link_token(user)

      # This user has TOTP, so the magic-link login funnels through the 2FA
      # challenge first; complete it to reach the final redirect.
      conn = post(conn, ~p"/users/log-in", %{"user" => %{"token" => token}})
      assert redirected_to(conn) == ~p"/users/totp"

      conn =
        post(conn, ~p"/users/totp", %{
          "totp" => %{"code" => NimbleTOTP.verification_code(user.totp_secret)}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/admin"
    end

    test "confirms unconfirmed user", %{conn: conn, unconfirmed_user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)
      refute user.confirmed_at

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => token},
          "_action" => "confirmed"
        })

      assert get_session(conn, :user_token)
      # New account with no passkey/2FA → nudged to enrollment.
      assert redirected_to(conn) == ~p"/users/security"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "User confirmed successfully."

      assert Accounts.get_user!(user.id).confirmed_at

      # Now do a logged in request and assert on the admin menu
      conn = get(conn, ~p"/admin")
      response = html_response(conn, 200)
      assert response =~ user.email
      assert response =~ ~p"/users/log-out"
    end

    test "redirects to login page when magic link is invalid", %{conn: conn} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => "invalid"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "The link is invalid or it has expired."

      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "POST /users/log-in - passkey handoff" do
    test "logs the user in with a valid token", %{conn: conn, user: user} do
      token = Phoenix.Token.sign(BbhWeb.Endpoint, "passkey_session", user.id)

      conn = post(conn, ~p"/users/log-in", %{"user" => %{"passkey_token" => token}})

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/admin"
    end

    test "bypasses TOTP even when the user has it enabled", %{conn: conn, user: user} do
      {:ok, user} = Accounts.enable_totp(user, Accounts.generate_totp_secret())
      token = Phoenix.Token.sign(BbhWeb.Endpoint, "passkey_session", user.id)

      conn = post(conn, ~p"/users/log-in", %{"user" => %{"passkey_token" => token}})

      assert get_session(conn, :user_token)
      refute get_session(conn, :totp_pending_user_id)
      assert redirected_to(conn) == ~p"/admin"
    end

    test "redirects with an error for an invalid or expired token", %{conn: conn} do
      conn = post(conn, ~p"/users/log-in", %{"user" => %{"passkey_token" => "garbage"}})

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Anmeldung abgelaufen"
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "POST /users/log-in - unrecognized params" do
    test "fails closed without crashing on a no-JS email-only submit", %{conn: conn} do
      # The magic-link form falls back to a native POST when JS is off; it only
      # carries the email, which matches no credential clause. Must redirect, not 500.
      conn = post(conn, ~p"/users/log-in", %{"user" => %{"email" => "someone@example.com"}})

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Anmeldung fehlgeschlagen"
      assert redirected_to(conn) == ~p"/users/log-in"
      refute get_session(conn, :user_token)
    end
  end

  describe "DELETE /users/log-out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end
  end
end
