defmodule Bbh.AnalyticsTest do
  use Bbh.DataCase, async: true

  import Bbh.ContentFixtures

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

  describe "top_articles/3 and article_views/2" do
    test "attributes page views to articles by their current URL" do
      popular = article_fixture(title: "Schützenfest")
      quiet = article_fixture(title: "Jahreshauptversammlung")
      article_fixture(title: "Ungelesen")

      Analytics.record(%{path: article_path(popular), day: @today})
      Analytics.record(%{path: article_path(popular), day: @today})
      Analytics.record(%{path: article_path(quiet), day: @today})
      # Not an article page.
      Analytics.record(%{path: "/aktuell", day: @today})

      assert [
               %{id: popular_id, title: "Schützenfest", views: 2, path: popular_path},
               %{title: "Jahreshauptversammlung", views: 1}
             ] = Analytics.top_articles(@today, @today)

      assert popular_id == popular.id
      assert popular_path == article_path(popular)

      assert Analytics.article_views(@today, @today) == %{popular.id => 2, quiet.id => 1}
    end

    test "tells a slug's years apart and only counts the URL as it is built" do
      this_year = article_fixture(slug: "schuetzenfest")

      last_year =
        article_fixture(
          slug: "schuetzenfest",
          date_published: DateTime.add(DateTime.utc_now(:second), -400, :day)
        )

      refute last_year.year == this_year.year

      Analytics.record(%{path: article_path(this_year), day: @today})
      Analytics.record(%{path: article_path(last_year), day: @today})
      Analytics.record(%{path: article_path(last_year), day: @today})
      # Not the article's URL, though it would parse to the same year.
      Analytics.record(%{path: "/aktuell/0#{this_year.year}/schuetzenfest", day: @today})

      assert Analytics.article_views(@today, @today) == %{this_year.id => 1, last_year.id => 2}
    end

    test "only counts views inside the range" do
      article = article_fixture()
      Analytics.record(%{path: article_path(article), day: Date.add(@today, -40)})

      assert Analytics.top_articles(Date.add(@today, -29), @today) == []
      assert Analytics.article_views(Date.add(@today, -29), @today) == %{}
    end
  end

  describe "record_search/1 and top_searches/3" do
    test "counts normalized terms and searches without results" do
      Analytics.record_search(%{term: "Schützenfest", hits: 3, day: @today})
      Analytics.record_search(%{term: "  schützenfest ", hits: 3, day: @today})
      Analytics.record_search(%{term: "Kaiserschießen", hits: 0, day: @today})

      assert Analytics.top_searches(@today, @today) == [
               %{term: "schützenfest", searches: 2, no_results: 0},
               %{term: "kaiserschießen", searches: 1, no_results: 1}
             ]
    end

    test "caps new terms per day but keeps counting known ones" do
      now = DateTime.utc_now(:second)

      rows =
        for i <- 1..500,
            do: %{day: @today, term: "t#{i}", searches: 1, inserted_at: now, updated_at: now}

      Repo.insert_all(Bbh.Analytics.DailySearch, rows)

      assert :ok = Analytics.record_search(%{term: "neu", hits: 0, day: @today})
      assert :ok = Analytics.record_search(%{term: "t1", hits: 2, day: @today})

      top = Analytics.top_searches(@today, @today, 600)
      refute Enum.any?(top, &(&1.term == "neu"))
      assert %{searches: 2} = Enum.find(top, &(&1.term == "t1"))

      # Another day has room again.
      assert :ok = Analytics.record_search(%{term: "neu", hits: 0, day: Date.add(@today, -1)})
      assert [%{term: "neu"}] = Analytics.top_searches(Date.add(@today, -1), Date.add(@today, -1))
    end

    test "prune_searches/1 drops days past the retention" do
      today = Date.utc_today()
      Analytics.record_search(%{term: "alt", hits: 1, day: Date.add(today, -401)})
      Analytics.record_search(%{term: "grenze", hits: 1, day: Date.add(today, -400)})

      assert Analytics.prune_searches() == 1

      assert [%{term: "grenze"}] =
               Analytics.top_searches(Date.add(today, -401), today)
    end

    test "ignores blank terms" do
      assert :ok = Analytics.record_search(%{term: "   ", hits: 0})
      assert :ok = Analytics.record_search(%{})

      assert Analytics.top_searches(@today, @today) == []
    end

    test "normalize_term/1 collapses whitespace, lower-cases and truncates" do
      assert Analytics.normalize_term(" Thron \n 2026 ") == "thron 2026"
      assert Analytics.normalize_term(String.duplicate("a", 300)) |> String.length() == 100
      assert Analytics.normalize_term(nil) == ""
    end
  end

  defp article_path(article), do: "/aktuell/#{article.year}/#{article.slug}"

  describe "record_ical/1 and ical_summary/2" do
    test "counts total fetches and peak daily unique subscribers" do
      Analytics.record_ical(%{visitor_hash: "a", day: @today})
      Analytics.record_ical(%{visitor_hash: "a", day: @today})
      Analytics.record_ical(%{visitor_hash: "b", day: @today})

      assert %{fetches: 3, subscribers: 2} = Analytics.ical_summary(@today, @today)
    end

    test "subscribers is the peak daily unique count, not the range sum" do
      yesterday = Date.add(@today, -1)
      Analytics.record_ical(%{visitor_hash: "a", day: yesterday})
      Analytics.record_ical(%{visitor_hash: "a", day: @today})
      Analytics.record_ical(%{visitor_hash: "b", day: @today})

      assert %{fetches: 3, subscribers: 2} = Analytics.ical_summary(yesterday, @today)
    end

    test "ignores retrievals without a visitor hash" do
      assert :ok = Analytics.record_ical(%{})

      assert %{fetches: 0, subscribers: 0} = Analytics.ical_summary(@today, @today)
    end
  end

  describe "ical_clients/2" do
    test "breaks retrievals down by client family, busiest first" do
      yesterday = Date.add(@today, -1)

      Analytics.record_ical(%{visitor_hash: "a", client: "apple", day: @today})
      Analytics.record_ical(%{visitor_hash: "a", client: "apple", day: @today})
      Analytics.record_ical(%{visitor_hash: "b", client: "apple", day: @today})
      Analytics.record_ical(%{visitor_hash: "c", client: "google", day: yesterday})
      Analytics.record_ical(%{visitor_hash: "d", client: "google", day: @today})

      assert [
               %{client: "apple", label: "Apple Kalender", subscribers: 2, fetches: 3},
               %{client: "google", label: "Google Kalender", subscribers: 1, fetches: 2}
             ] = Analytics.ical_clients(yesterday, @today)
    end

    test "rows without a client are listed as Unbekannt" do
      Analytics.record_ical(%{visitor_hash: "a", day: @today})

      assert [%{client: nil, label: "Unbekannt", subscribers: 1, fetches: 1}] =
               Analytics.ical_clients(@today, @today)
    end
  end

  describe "roll_up/1" do
    alias Bbh.Analytics.{DailyVisitor, IcalFetch}

    # Two days past the window, one inside it.
    setup do
      old = Date.add(@today, -9)
      older = Date.add(@today, -10)
      recent = Date.add(@today, -3)

      for {hash, day} <- [{"a", older}, {"b", older}, {"a", old}, {"c", recent}] do
        Analytics.record(%{path: "/", visitor_hash: hash, day: day})
      end

      for {hash, client, day} <- [
            {"a", "apple", older},
            {"a", "apple", older},
            {"b", "apple", older},
            {"c", nil, older},
            {"d", "google", old},
            {"e", "google", recent}
          ] do
        Analytics.record_ical(%{visitor_hash: hash, client: client, day: day})
      end

      %{old: old, older: older, recent: recent}
    end

    test "deletes every hash row past the window and keeps the recent ones", ctx do
      assert {:ok, %{visitors: 3, ical: 4}} = Analytics.roll_up(7)

      assert Repo.all(from v in DailyVisitor, select: v.day) == [ctx.recent]
      assert Repo.all(from f in IcalFetch, select: f.day) == [ctx.recent]
    end

    test "the dashboard numbers are the same before and after", ctx do
      from = ctx.older
      to = @today

      before = dashboard(from, to)
      assert {:ok, _} = Analytics.roll_up(7)
      assert dashboard(from, to) == before

      # And the figures are the ones recorded, not merely equal to each other.
      assert %{visits: 4} = Analytics.summary(from, to)
      assert %{fetches: 6, subscribers: 3} = Analytics.ical_summary(from, to)

      assert [
               %{client: "apple", subscribers: 2, fetches: 3},
               %{client: "google", subscribers: 1, fetches: 2},
               %{client: nil, subscribers: 1, fetches: 1}
             ] = Analytics.ical_clients(from, to)
    end

    test "is idempotent and adds a late row to an existing total", ctx do
      assert {:ok, _} = Analytics.roll_up(7)
      assert {:ok, %{visitors: 0, ical: 0}} = Analytics.roll_up(7)

      # A hash row for an already rolled-up day (cannot happen through record/1, which
      # always writes today) is added to the total, not overwritten by it.
      Analytics.record(%{path: "/", visitor_hash: "z", day: ctx.older})
      Analytics.record_ical(%{visitor_hash: "z", client: nil, day: ctx.older})
      assert {:ok, %{visitors: 1, ical: 1}} = Analytics.roll_up(7)

      assert %{visits: 3} = Analytics.summary(ctx.older, ctx.older)
      assert %{fetches: 5, subscribers: 4} = Analytics.ical_summary(ctx.older, ctx.older)
    end

    defp dashboard(from, to) do
      %{
        summary: Analytics.summary(from, to),
        visitors: Analytics.visitors_by_day(from, to),
        ical: Analytics.ical_summary(from, to),
        clients: Analytics.ical_clients(from, to)
      }
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
