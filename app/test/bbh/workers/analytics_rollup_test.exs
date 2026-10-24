defmodule Bbh.Workers.AnalyticsRollupTest do
  use Bbh.DataCase, async: true

  alias Bbh.Analytics
  alias Bbh.Analytics.DailyVisitor
  alias Bbh.Workers.AnalyticsRollup

  test "rolls up hashes older than seven days and keeps the last seven" do
    today = Date.utc_today()
    Analytics.record(%{path: "/", visitor_hash: "old", day: Date.add(today, -8)})
    Analytics.record(%{path: "/", visitor_hash: "edge", day: Date.add(today, -7)})
    Analytics.record(%{path: "/", visitor_hash: "new", day: today})

    assert :ok = AnalyticsRollup.perform(%Oban.Job{})

    assert Repo.all(from v in DailyVisitor, select: v.visitor_hash, order_by: v.day) ==
             ["edge", "new"]

    assert %{visits: 3} = Analytics.summary(Date.add(today, -8), today)
  end
end
