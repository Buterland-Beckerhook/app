defmodule BbhWeb.Admin.SettingsLiveTest do
  # async: false — the passkey happy path runs the REAL Wax library via the
  # software authenticator; must never overlap the Wax-stubbing modules (see the
  # ceremony test and LoginPasskeyTest).
  use BbhWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Bbh.AccountsFixtures

  alias Bbh.Accounts
  alias Bbh.Accounts.Passkeys
  alias Bbh.Accounts.User
  alias Bbh.WebAuthnSoftwareAuthenticator, as: Authenticator

  describe "Account section" do
    test "renders the settings modal with section tabs", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/admin/einstellungen")

      assert html =~ "Change Email"
      assert html =~ "Account"
      assert html =~ "Passkeys"
      assert html =~ "2FA"
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/admin/einstellungen")

      assert {:redirect, %{to: path}} = redirect
      assert path == ~p"/users/log-in"
    end

    test "redirects if user is not in sudo mode", %{conn: conn} do
      {:ok, conn} =
        conn
        |> log_in_user(user_fixture(),
          token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
        )
        |> live(~p"/admin/einstellungen")
        |> follow_redirect(conn, ~p"/users/log-in")

      assert conn.resp_body =~ "You must re-authenticate to access this page."
    end
  end

  describe "update email form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "updates the user email", %{conn: conn, user: user} do
      new_email = unique_user_email()

      {:ok, lv, _html} = live(conn, ~p"/admin/einstellungen")

      result =
        lv
        |> form("#email_form", %{"user" => %{"email" => new_email}})
        |> render_submit()

      assert result =~ "A link to confirm your email"
      assert Accounts.get_user_by_email(user.email)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/einstellungen")

      result =
        lv
        |> element("#email_form")
        |> render_change(%{
          "action" => "update_email",
          "user" => %{"email" => "with spaces"}
        })

      assert result =~ "Change Email"
      assert result =~ "must have the @ sign and no spaces"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/admin/einstellungen")

      result =
        lv
        |> form("#email_form", %{"user" => %{"email" => user.email}})
        |> render_submit()

      assert result =~ "Change Email"
      assert result =~ "did not change"
    end
  end

  describe "confirm email" do
    setup %{conn: conn} do
      user = user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{conn: log_in_user(conn, user), token: token, email: email, user: user}
    end

    test "updates the user email once", %{conn: conn, user: user, token: token, email: email} do
      {:error, redirect} = live(conn, ~p"/admin/einstellungen/confirm-email/#{token}")

      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/admin/einstellungen"
      assert %{"info" => message} = flash
      assert message == "Email changed successfully."
      refute Accounts.get_user_by_email(user.email)
      assert Accounts.get_user_by_email(email)

      # use confirm token again
      {:error, redirect} = live(conn, ~p"/admin/einstellungen/confirm-email/#{token}")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/admin/einstellungen"
      assert %{"error" => message} = flash
      assert message == "Email change link is invalid or it has expired."
    end

    test "does not update email with invalid token", %{conn: conn, user: user} do
      {:error, redirect} = live(conn, ~p"/admin/einstellungen/confirm-email/oops")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/admin/einstellungen"
      assert %{"error" => message} = flash
      assert message == "Email change link is invalid or it has expired."
      assert Accounts.get_user_by_email(user.email)
    end

    test "redirects if user is not logged in", %{token: token} do
      conn = build_conn()
      {:error, redirect} = live(conn, ~p"/admin/einstellungen/confirm-email/#{token}")
      assert {:redirect, %{to: path}} = redirect
      assert path == ~p"/users/log-in"
    end
  end

  describe "2FA section — sudo mode" do
    setup :register_and_log_in_admin

    @tag token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -30, :minute)
    test "redirects to log-in when not in sudo mode", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, ~p"/admin/einstellungen/2fa")
    end
  end

  describe "2FA section — setup (no TOTP yet)" do
    setup :register_and_log_in_admin

    test "renders the enable form with a QR code", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/admin/einstellungen/2fa")

      assert html =~ "Zwei-Faktor"
      assert html =~ "Aktivieren"
      assert html =~ "<svg"
    end

    test "rejects an invalid code", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/einstellungen/2fa")

      html = lv |> element("form[phx-submit=enable]") |> render_submit(%{"code" => "000000"})
      assert html =~ "Ungültiger Code"
    end

    test "enables TOTP with a valid code", %{conn: conn, user: user} do
      {:ok, lv, html} = live(conn, ~p"/admin/einstellungen/2fa")

      secret = extract_secret(html)
      code = NimbleTOTP.verification_code(secret)

      html = lv |> element("form[phx-submit=enable]") |> render_submit(%{"code" => code})

      assert html =~ "Zwei-Faktor ist für dein Konto aktiviert"
      assert User.totp_enabled?(Accounts.get_user!(user.id))
    end
  end

  describe "2FA section — removal (TOTP enabled)" do
    setup :register_and_log_in_admin

    setup %{user: user} do
      {:ok, user} = Accounts.enable_totp(user, Accounts.generate_totp_secret())
      %{user: user}
    end

    test "shows the enabled state and disables it", %{conn: conn, user: user} do
      {:ok, lv, html} = live(conn, ~p"/admin/einstellungen/2fa")
      assert html =~ "aktiviert"

      html = render_click(lv, "disable")
      assert html =~ "Aktivieren"
      refute User.totp_enabled?(Accounts.get_user!(user.id))
    end
  end

  describe "Passkeys section — access control" do
    setup :register_and_log_in_user

    test "redirects when not logged in", %{conn: _conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(build_conn(), ~p"/admin/einstellungen/passkeys")
    end

    @tag token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -30, :minute)
    test "redirects when not in sudo mode", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(conn, ~p"/admin/einstellungen/passkeys")
    end
  end

  describe "Passkeys section — listing" do
    setup :register_and_log_in_user

    test "shows the empty state when there are no passkeys", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/admin/einstellungen/passkeys")
      assert html =~ "Passkeys"
      assert html =~ "noch keinen Passkey"
    end

    test "lists the user's passkeys", %{conn: conn, user: user} do
      passkey_fixture(user, nickname: "Mein YubiKey")
      {:ok, _lv, html} = live(conn, ~p"/admin/einstellungen/passkeys")
      assert html =~ "Mein YubiKey"
    end
  end

  describe "Passkeys section — registration" do
    setup :register_and_log_in_user

    test "renders the create options with a challenge and user block", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/admin/einstellungen/passkeys")

      # The options are a JSON blob in the hook's data attribute (HTML-escaped),
      # so the click handler can start the ceremony without a server round-trip.
      assert html =~ ~s(data-passkey-ceremony="create")
      assert html =~ "&quot;challenge&quot;"
      assert html =~ "&quot;residentKey&quot;:&quot;required&quot;"
      assert html =~ "&quot;user&quot;"
    end

    test "registers a passkey through the real ceremony", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/admin/einstellungen/passkeys")

      # Sign the challenge the LiveView actually embedded, then push the result
      # back exactly as the JS hook would.
      {params, _keys} = Authenticator.register(challenge_from(html))

      html = render_hook(lv, "register_credential", Map.put(params, "nickname", "Laptop"))

      assert html =~ "Passkey hinzugefügt"
      assert html =~ "Laptop"
    end

    test "shows an error when the nickname is blank", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/einstellungen/passkeys")

      # The hook refuses to open the authenticator for a blank name and signals it.
      html = render_hook(lv, "nickname_blank", %{})
      assert html =~ "Bitte einen Namen"
    end

    test "guards a blank nickname pushed alongside a credential", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/admin/einstellungen/passkeys")
      {params, _keys} = Authenticator.register(challenge_from(html))

      html = render_hook(lv, "register_credential", Map.put(params, "nickname", "   "))
      assert html =~ "Bitte einen Namen"
    end

    test "shows an error when the credential fails verification", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/admin/einstellungen/passkeys")

      # A well-formed credential signed against a foreign challenge — real Wax
      # rejects it cleanly (challenge mismatch), so we hit the error branch.
      {params, _keys} = Authenticator.register(Passkeys.new_registration_challenge(user))

      html = render_hook(lv, "register_credential", Map.put(params, "nickname", "Laptop"))
      assert html =~ "Passkey konnte nicht registriert werden"
    end
  end

  describe "Passkeys section — deletion" do
    setup :register_and_log_in_user

    test "removes a passkey", %{conn: conn, user: user} do
      passkey = passkey_fixture(user, nickname: "Alt")
      {:ok, lv, html} = live(conn, ~p"/admin/einstellungen/passkeys")
      assert html =~ "Alt"

      html = lv |> element("button[phx-value-id='#{passkey.id}']") |> render_click()

      refute html =~ "Alt"
      assert Passkeys.list_passkeys(user) == []
    end
  end

  describe "section navigation" do
    setup :register_and_log_in_admin

    test "patches between sections without a full reload", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/einstellungen")

      html = lv |> element("a[role='tab'][href='/admin/einstellungen/2fa']") |> render_click()
      assert html =~ "Zwei-Faktor-Authentifizierung"
      assert_patched(lv, ~p"/admin/einstellungen/2fa")

      html = lv |> element("a[role='tab'][href='/admin/einstellungen']") |> render_click()
      assert html =~ "Change Email"
      assert_patched(lv, ~p"/admin/einstellungen")
    end
  end

  # Pull the Base32-encoded secret out of the stable #totp-secret span.
  defp extract_secret(html) do
    [_, encoded] = Regex.run(~r{id="totp-secret"[^>]*>([A-Z2-7]+)<}, html)
    Base.decode32!(encoded, padding: false)
  end

  # Reconstruct the in-flight challenge from the embedded (HTML-escaped) options so
  # the software authenticator signs exactly what the server will verify against —
  # the bytes, origin and rp_id are all the authenticator reads.
  defp challenge_from(html) do
    [_, b64] = Regex.run(~r/&quot;challenge&quot;:&quot;([A-Za-z0-9_-]+)&quot;/, html)

    %Wax.Challenge{
      type: :attestation,
      issued_at: System.os_time(:second),
      bytes: Base.url_decode64!(b64, padding: false),
      rp_id: BbhWeb.Endpoint.host(),
      origin: BbhWeb.Endpoint.url()
    }
  end
end
