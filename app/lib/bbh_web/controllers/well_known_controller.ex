defmodule BbhWeb.WellKnownController do
  @moduledoc """
  Well-known URIs served by the app itself: `security.txt` (RFC 9116).

  No `/.well-known/change-password`: the site has no passwords (magic link or passkey,
  plus TOTP), so there is nothing a password manager could send a user to change.
  """
  use BbhWeb, :controller

  # RFC 9116 §2.5.5: "Expires" is required and SHOULD be less than a year in the
  # future. Generated per request so the file can never lapse unnoticed; the contact
  # address itself comes from config (`:security_contact`).
  @expires_in_days 180

  def security_txt(conn, _params) do
    base = Application.get_env(:bbh, :site_url, "https://buterland-beckerhook.de")
    contact = Application.fetch_env!(:bbh, :security_contact)

    expires =
      Date.utc_today()
      |> Date.add(@expires_in_days)
      |> DateTime.new!(~T[00:00:00], "Etc/UTC")
      |> DateTime.to_iso8601()

    body = """
    Contact: mailto:#{contact}
    Expires: #{expires}
    Preferred-Languages: de, en
    Canonical: #{base}/.well-known/security.txt
    """

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, body)
  end
end
