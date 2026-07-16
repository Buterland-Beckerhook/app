defmodule BbhWeb.TotpControllerTest do
  use BbhWeb.ConnCase, async: true

  import Bbh.AccountsFixtures

  alias Bbh.Accounts

  defp pending(conn, user) do
    conn |> init_test_session(%{}) |> put_session(:totp_pending_user_id, user.id)
  end

  test "GET /users/totp without a pending login redirects to log-in", %{conn: conn} do
    conn = get(conn, ~p"/users/totp")
    assert redirected_to(conn) == ~p"/users/log-in"
  end

  test "GET /users/totp with a pending login renders the challenge", %{conn: conn} do
    user = user_fixture()
    conn = conn |> pending(user) |> get(~p"/users/totp")
    assert html_response(conn, 200)
  end

  describe "POST /users/totp" do
    setup do
      secret = Accounts.generate_totp_secret()
      {:ok, user} = Accounts.enable_totp(user_fixture(), secret)
      %{user: user, secret: secret}
    end

    test "logs the user in with a valid code", %{conn: conn, user: user, secret: secret} do
      code = NimbleTOTP.verification_code(secret)
      conn = conn |> pending(user) |> post(~p"/users/totp", %{"totp" => %{"code" => code}})

      # TOTP is set but this user has no passkey yet → nudged to enrollment.
      assert redirected_to(conn) == ~p"/users/security"
      assert get_session(conn, :user_token)
    end

    test "sends a user who already has a passkey to the admin area", %{
      conn: conn,
      user: user,
      secret: secret
    } do
      passkey_fixture(user)
      code = NimbleTOTP.verification_code(secret)
      conn = conn |> pending(user) |> post(~p"/users/totp", %{"totp" => %{"code" => code}})

      assert redirected_to(conn) == ~p"/admin"
      assert get_session(conn, :user_token)
    end

    test "re-renders with an error on an invalid code", %{conn: conn, user: user} do
      conn = conn |> pending(user) |> post(~p"/users/totp", %{"totp" => %{"code" => "000000"}})
      assert html_response(conn, 200) =~ "Ungültiger Code"
    end
  end
end
