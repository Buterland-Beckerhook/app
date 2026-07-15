defmodule BbhWeb.UserLive.LoginTest do
  use BbhWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Bbh.AccountsFixtures

  describe "login page" do
    test "renders login page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "Anmelden"
      assert html =~ "Interner Bereich für Redakteure des Vereins."
      assert html =~ "Log in with email"
      assert html =~ "Mit Passkey anmelden"
    end
  end

  describe "user login - passkey" do
    test "embeds the get options for the hook and wires the button to it", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/log-in")

      # The challenge is embedded up front so the click handler can call WebAuthn
      # with no server round-trip (Safari needs the user-activation window); the
      # button is driven by the hook, not phx-click.
      assert html =~ "data-passkey-trigger"
      assert html =~ ~s(data-passkey-ceremony="get")
      assert html =~ "&quot;challenge&quot;"
    end

    test "a malformed assertion is rejected without crashing", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      html =
        render_hook(lv, "passkey_login_assertion", %{
          "rawId" => "x",
          "authenticatorData" => "x",
          "signature" => "x",
          "clientDataJSON" => "x"
        })

      assert html =~ "Passkey-Anmeldung fehlgeschlagen"
    end
  end

  describe "user login - magic link" do
    test "sends magic link email when user exists", %{conn: conn} do
      user = user_fixture()

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      {:ok, _lv, html} =
        form(lv, "#login_form_magic", user: %{email: user.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "If your email is in our system"

      assert Bbh.Repo.get_by!(Bbh.Accounts.UserToken, user_id: user.id).context ==
               "login"
    end

    test "does not disclose if user is registered", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      {:ok, _lv, html} =
        form(lv, "#login_form_magic", user: %{email: "idonotexist@example.com"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "If your email is in our system"
    end
  end

  describe "re-authentication (sudo mode)" do
    setup %{conn: conn} do
      user = user_fixture()
      %{user: user, conn: log_in_user(conn, user)}
    end

    test "shows login page with email filled in", %{conn: conn, user: user} do
      {:ok, _lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "Bitte erneut anmelden, um sensible Aktionen durchzuführen."
      refute html =~ "Register"
      assert html =~ "Log in with email"

      assert html =~
               ~s(<input type="email" name="user[email]" id="login_form_magic_email" value="#{user.email}")
    end
  end
end
