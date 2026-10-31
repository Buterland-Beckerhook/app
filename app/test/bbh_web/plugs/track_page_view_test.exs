defmodule BbhWeb.Plugs.TrackPageViewTest do
  # async: false — toggles the global tracking config for the duration.
  use BbhWeb.ConnCase, async: false

  import Bbh.CalendarFixtures

  @browser_ua "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120 Safari"

  setup do
    previous = Application.fetch_env(:bbh, BbhWeb.Plugs.TrackPageView)
    Application.put_env(:bbh, BbhWeb.Plugs.TrackPageView, enabled: true, async: false)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:bbh, BbhWeb.Plugs.TrackPageView, value)
        :error -> Application.delete_env(:bbh, BbhWeb.Plugs.TrackPageView)
      end
    end)

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

  test "records a retrieval of the iCal subscription feed", %{conn: conn} do
    conn |> put_req_header("user-agent", @browser_ua) |> get("/termine/abo.ics")

    assert %{fetches: fetches, subscribers: subs} = Bbh.Analytics.ical_summary(today(), today())
    assert fetches >= 1
    assert subs >= 1
    # The feed is not an HTML page view.
    assert %{views: 0} = Bbh.Analytics.summary(today(), today())
  end

  test "stores the calendar-client family, not the raw User-Agent", %{conn: conn} do
    conn
    |> put_req_header("user-agent", "iOS/18.1 (22B83) dataaccessd/1.0")
    |> get("/termine/abo.ics")

    assert [%{client: "apple", subscribers: 1}] =
             Bbh.Analytics.ical_clients(today(), today())

    assert [row] = Bbh.Repo.all(Bbh.Analytics.IcalFetch)
    assert row.client == "apple"
  end

  test "does not count single-event .ics downloads as feed fetches", %{conn: conn} do
    event = event_fixture()

    conn
    |> put_req_header("user-agent", @browser_ua)
    |> get("/termine/#{event.year}/#{event.slug}/event.ics")

    assert %{fetches: 0} = Bbh.Analytics.ical_summary(today(), today())
  end
end
