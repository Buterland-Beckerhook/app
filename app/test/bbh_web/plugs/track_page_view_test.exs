defmodule BbhWeb.Plugs.TrackPageViewTest do
  # async: false — toggles the global tracking config for the duration.
  use BbhWeb.ConnCase

  @browser_ua "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120 Safari"

  setup do
    Application.put_env(:bbh, BbhWeb.Plugs.TrackPageView, enabled: true, async: false)
    on_exit(fn -> Application.put_env(:bbh, BbhWeb.Plugs.TrackPageView, enabled: false) end)
    :ok
  end

  defp today, do: Date.utc_today()

  test "records a public HTML page view", %{conn: conn} do
    conn |> put_req_header("user-agent", @browser_ua) |> get(~p"/kontakt")

    assert %{views: views} = Bbh.Analytics.summary(today(), today())
    assert views >= 1
    assert Enum.any?(Bbh.Analytics.top_pages(today(), today()), &(&1.path == "/kontakt"))
  end

  test "ignores obvious bots", %{conn: conn} do
    ua = "Googlebot/2.1 (+http://www.google.com/bot.html)"
    conn |> put_req_header("user-agent", ua) |> get(~p"/kontakt")

    assert %{views: 0} = Bbh.Analytics.summary(today(), today())
  end

  test "skips the admin area", %{conn: conn} do
    conn |> put_req_header("user-agent", @browser_ua) |> get("/admin")

    assert %{views: 0} = Bbh.Analytics.summary(today(), today())
  end
end
