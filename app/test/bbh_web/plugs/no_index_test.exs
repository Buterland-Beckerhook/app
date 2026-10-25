defmodule BbhWeb.Plugs.NoIndexTest do
  use BbhWeb.ConnCase

  # The whole point of the beta flag is that the public beta cannot be indexed even if the
  # reverse-proxy noindex middleware is ever dropped, and that nobody mistakes it for the
  # live site. These pin both branches: everything is present exactly when the flag is on,
  # and absent (prod default) when it is off.

  @directives "noindex, nofollow, noarchive, noimageindex, noai, noimageai"

  defp robots_tag(conn), do: conn |> get_resp_header("x-robots-tag") |> List.first()

  setup do
    original = Application.get_env(:bbh, :beta, false)
    on_exit(fn -> Application.put_env(:bbh, :beta, original) end)
  end

  describe "beta" do
    setup do
      Application.put_env(:bbh, :beta, true)
    end

    test "stamps X-Robots-Tag on every response", %{conn: conn} do
      assert conn |> get(~p"/") |> robots_tag() == @directives
      # Static assets are served by Plug.Static, which the plug still covers via before_send.
      assert conn |> get(~p"/favicon.ico") |> robots_tag() == @directives
      assert conn |> get(~p"/robots.txt") |> robots_tag() == @directives
    end

    test "robots.txt turns every crawler away", %{conn: conn} do
      body = conn |> get(~p"/robots.txt") |> text_response(200)

      assert body =~ "User-agent: *\nDisallow: /\n"
      assert body =~ "User-agent: GPTBot\nDisallow: /\n"
      assert body =~ "User-agent: ClaudeBot\nDisallow: /\n"
      refute body =~ "Allow: /\n"
      refute body =~ "Sitemap:"
    end

    test "every page carries the banners, meta robots and a canonical link to the live site",
         %{conn: conn} do
      html = conn |> get(~p"/termine?jahr=2026") |> html_response(200)

      assert html =~ ~s(<meta name="robots" content="#{@directives}">)
      assert html =~ ~s(<link rel="canonical" href="https://buterland-beckerhook.de/termine">)

      for id <- ~w(beta-banner-top beta-banner-bottom) do
        assert html =~ ~s(id="#{id}")
      end

      # The banner leads to the same page on the live site, query included.
      assert count(html, ~s(href="https://buterland-beckerhook.de/termine?jahr=2026")) == 2
    end
  end

  describe "live site (prod default)" do
    setup do
      Application.put_env(:bbh, :beta, false)
    end

    test "no header, banner or canonical link", %{conn: conn} do
      conn = get(conn, ~p"/")
      html = html_response(conn, 200)

      assert robots_tag(conn) == nil
      refute html =~ "beta-banner"
      refute html =~ ~s(name="robots")
      refute html =~ ~s(rel="canonical")
    end

    test "robots.txt allows crawling and points at the sitemap", %{conn: conn} do
      body = conn |> get(~p"/robots.txt") |> text_response(200)

      assert body =~ "User-agent: *\nAllow: /\nDisallow: /admin\n"
      assert body =~ ~r{Sitemap: https?://.+/sitemap\.xml}
    end
  end

  defp count(haystack, needle), do: length(String.split(haystack, needle)) - 1
end
