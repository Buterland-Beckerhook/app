defmodule BbhWeb.WellKnownControllerTest do
  use BbhWeb.ConnCase, async: true

  describe "GET /.well-known/security.txt" do
    test "serves the RFC 9116 fields as plain text", %{conn: conn} do
      conn = get(conn, ~p"/.well-known/security.txt")

      assert response_content_type(conn, :text) =~ "text/plain"
      body = response(conn, 200)

      assert body =~ "Contact: mailto:webmaster@buterland-beckerhook.de\n"
      assert body =~ "Preferred-Languages: de, en\n"
      assert body =~ ~r{Canonical: https?://\S+/\.well-known/security\.txt\n}
    end

    test "Expires is in the future but less than a year away", %{conn: conn} do
      body = conn |> get(~p"/.well-known/security.txt") |> response(200)

      [_, stamp] = Regex.run(~r/^Expires: (\S+)$/m, body)
      {:ok, expires, 0} = DateTime.from_iso8601(stamp)
      now = DateTime.utc_now()

      assert DateTime.compare(expires, now) == :gt
      assert DateTime.diff(expires, now, :day) < 365
    end
  end

  describe "root-level icons" do
    test "apple-touch icons are served at the paths iOS probes", %{conn: conn} do
      for path <- ["/apple-touch-icon.png", "/apple-touch-icon-precomposed.png"] do
        conn = get(conn, path)
        assert conn.status == 200, "expected #{path} to be served"
        assert response_content_type(conn, :png) =~ "image/png"
      end
    end

    test "the layout links the icons", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ ~s(rel="apple-touch-icon" href="/apple-touch-icon.png")
      assert html =~ ~s(href="/images/logo.svg" type="image/svg+xml")
      assert html =~ ~r{property="og:image" content="https?://[^"]+/images/og-logo\.png"}
    end
  end
end
