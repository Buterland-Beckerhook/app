defmodule BbhWeb.UserLive.TotpTest do
  use BbhWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Bbh.Accounts
  alias Bbh.Accounts.User

  setup :register_and_log_in_admin

  describe "sudo mode" do
    @tag token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -30, :minute)
    test "redirects to log-in when not in sudo mode", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/users/2fa")
    end
  end

  describe "setup (no TOTP yet)" do
    test "renders the enable form with a QR code", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/2fa")

      assert html =~ "Zwei-Faktor"
      assert html =~ "Aktivieren"
      assert html =~ "<svg"
    end

    test "rejects an invalid code", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/2fa")

      html = lv |> element("form[phx-submit=enable]") |> render_submit(%{"code" => "000000"})
      assert html =~ "Ungültiger Code"
    end

    test "enables TOTP with a valid code", %{conn: conn, user: user} do
      {:ok, lv, html} = live(conn, ~p"/users/2fa")

      secret = extract_secret(html)
      code = NimbleTOTP.verification_code(secret)

      html = lv |> element("form[phx-submit=enable]") |> render_submit(%{"code" => code})

      assert html =~ "Zwei-Faktor ist für dein Konto aktiviert"
      assert User.totp_enabled?(Accounts.get_user!(user.id))
    end
  end

  describe "removal (TOTP enabled)" do
    setup %{user: user} do
      {:ok, user} = Accounts.enable_totp(user, Accounts.generate_totp_secret())
      %{user: user}
    end

    test "shows the enabled state and disables it", %{conn: conn, user: user} do
      {:ok, lv, html} = live(conn, ~p"/users/2fa")
      assert html =~ "aktiviert"

      html = render_click(lv, "disable")
      assert html =~ "Aktivieren"
      refute User.totp_enabled?(Accounts.get_user!(user.id))
    end
  end

  # Pull the Base32-encoded secret out of the stable #totp-secret span.
  defp extract_secret(html) do
    [_, encoded] = Regex.run(~r{id="totp-secret"[^>]*>([A-Z2-7]+)<}, html)
    Base.decode32!(encoded, padding: false)
  end
end
