defmodule Bbh.AnalyticsTest do
  use Bbh.DataCase, async: true

  alias Bbh.Analytics

  @today Date.utc_today()

  describe "record/1" do
    test "increments page-view counts per day+path" do
      Analytics.record(%{path: "/aktuell", day: @today})
      Analytics.record(%{path: "/aktuell", day: @today})
      Analytics.record(%{path: "/termine", day: @today})

      assert %{views: 3} = Analytics.summary(@today, @today)

      assert Analytics.top_pages(@today, @today) == [
               %{path: "/aktuell", views: 2},
               %{path: "/termine", views: 1}
             ]
    end

    test "counts distinct visitors once per day" do
      Analytics.record(%{path: "/", visitor_hash: "abc", day: @today})
      Analytics.record(%{path: "/", visitor_hash: "abc", day: @today})
      Analytics.record(%{path: "/", visitor_hash: "def", day: @today})

      assert %{visits: 2} = Analytics.summary(@today, @today)
    end

    test "aggregates external referrer hosts, ignoring blank ones" do
      Analytics.record(%{path: "/", referrer_host: "google.com", day: @today})
      Analytics.record(%{path: "/", referrer_host: "google.com", day: @today})
      Analytics.record(%{path: "/", referrer_host: nil, day: @today})

      assert Analytics.top_referrers(@today, @today) == [%{host: "google.com", views: 2}]
    end
  end

  describe "time-series" do
    test "views_by_day gap-fills the whole range oldest-first" do
      yesterday = Date.add(@today, -1)
      Analytics.record(%{path: "/", day: @today})

      series = Analytics.views_by_day(yesterday, @today)

      assert series == [%{day: yesterday, count: 0}, %{day: @today, count: 1}]
    end
  end
end
