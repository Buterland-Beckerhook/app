defmodule BbhWeb.UserLive.PasskeysTest do
  # async: false — the happy path runs the REAL Wax library via the software
  # authenticator; must never overlap the Wax-stubbing modules (see the ceremony
  # test and LoginPasskeyTest).
  use BbhWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Bbh.AccountsFixtures

  alias Bbh.Accounts.Passkeys
  alias Bbh.WebAuthnSoftwareAuthenticator, as: Authenticator

  setup :register_and_log_in_user

  describe "access control" do
    test "redirects when not logged in", %{conn: _conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(build_conn(), ~p"/users/passkeys")
    end

    @tag token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -30, :minute)
    test "redirects when not in sudo mode", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/users/passkeys")
    end
  end

  describe "listing" do
    test "shows the empty state when there are no passkeys", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/passkeys")
      assert html =~ "Passkeys"
      assert html =~ "noch keinen Passkey"
    end

    test "lists the user's passkeys", %{conn: conn, user: user} do
      passkey_fixture(user, nickname: "Mein YubiKey")
      {:ok, _lv, html} = live(conn, ~p"/users/passkeys")
      assert html =~ "Mein YubiKey"
    end
  end

  describe "registration" do
    test "renders the create options with a challenge and user block", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/passkeys")

      # The options are a JSON blob in the hook's data attribute (HTML-escaped),
      # so the click handler can start the ceremony without a server round-trip.
      assert html =~ ~s(data-passkey-ceremony="create")
      assert html =~ "&quot;challenge&quot;"
      assert html =~ "&quot;residentKey&quot;:&quot;required&quot;"
      assert html =~ "&quot;user&quot;"
    end

    test "registers a passkey through the real ceremony", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/users/passkeys")

      # Sign the challenge the LiveView actually embedded, then push the result
      # back exactly as the JS hook would.
      {params, _keys} = Authenticator.register(challenge_from(html))

      html = render_hook(lv, "register_credential", Map.put(params, "nickname", "Laptop"))

      assert html =~ "Passkey hinzugefügt"
      assert html =~ "Laptop"
    end

    test "shows an error when the nickname is blank", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/passkeys")

      # The hook refuses to open the authenticator for a blank name and signals it.
      html = render_hook(lv, "nickname_blank", %{})
      assert html =~ "Bitte einen Namen"
    end

    test "guards a blank nickname pushed alongside a credential", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/users/passkeys")
      {params, _keys} = Authenticator.register(challenge_from(html))

      html = render_hook(lv, "register_credential", Map.put(params, "nickname", "   "))
      assert html =~ "Bitte einen Namen"
    end

    test "shows an error when the credential fails verification", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/passkeys")

      # A well-formed credential signed against a foreign challenge — real Wax
      # rejects it cleanly (challenge mismatch), so we hit the error branch.
      {params, _keys} = Authenticator.register(Passkeys.new_registration_challenge(user))

      html = render_hook(lv, "register_credential", Map.put(params, "nickname", "Laptop"))
      assert html =~ "Passkey konnte nicht registriert werden"
    end
  end

  describe "deletion" do
    test "removes a passkey", %{conn: conn, user: user} do
      passkey = passkey_fixture(user, nickname: "Alt")
      {:ok, lv, html} = live(conn, ~p"/users/passkeys")
      assert html =~ "Alt"

      html = lv |> element("button[phx-value-id='#{passkey.id}']") |> render_click()

      refute html =~ "Alt"
      assert Passkeys.list_passkeys(user) == []
    end
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
