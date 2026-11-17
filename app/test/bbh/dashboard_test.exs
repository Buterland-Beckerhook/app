defmodule Bbh.DashboardTest do
  use Bbh.DataCase, async: true

  import Bbh.ContentFixtures

  alias Bbh.Dashboard

  test "content_counts/0 groups by status" do
    article_fixture(%{status: "published"})
    article_fixture(%{status: "draft"})

    assert %{articles: %{"published" => 1, "draft" => 1}, events: %{}, people: 0, pages: %{}} =
             Dashboard.content_counts()
  end

  test "analytics/2 adds the admin-only figures only when asked" do
    Bbh.Analytics.record(%{path: "/termine", day: Date.utc_today()})

    basic = Dashboard.analytics(7, false)
    assert %{summary: %{views: 1}, top_pages: [%{path: "/termine"}]} = basic
    assert length(basic.by_day) == 7
    refute Map.has_key?(basic, :top_searches)

    full = Dashboard.analytics(7, true)

    assert Enum.sort(Map.keys(full) -- Map.keys(basic)) ==
             [:ical, :ical_clients, :push_subscriptions, :top_referrers, :top_searches]
  end
end
