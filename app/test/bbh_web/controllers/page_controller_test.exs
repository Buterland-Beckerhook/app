defmodule BbhWeb.PageControllerTest do
  use BbhWeb.ConnCase, async: true

  import Bbh.CalendarFixtures
  import Bbh.ContentFixtures

  alias BbhWeb.PageHTML

  test "GET / renders the homepage with the redesigned chrome", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    # Hero was removed with the redesign.
    refute html =~ "Willkommen im Buterland-Beckerhook"
    # Header: wordmark + CTA button (desktop and mobile menu).
    assert html =~ "Buterland-Beckerhook e.V."
    assert html =~ ~s(href="/verein/mitglied-werden")
    # Footer: section links, contact column, notifications opt-in.
    assert html =~ "Kontaktformular"
    assert html =~ "Datenschutz"
    assert html =~ ~s(id="push-optin")
    # Discreet user login link in the footer.
    assert html =~ ~s(href="/users/log-in")
    # First-visit push opt-in banner, hidden until app.js reveals it.
    assert html =~ ~s(id="push-banner" hidden)
  end

  test "GET / renders event banner, articles and throne when data exists", %{conn: conn} do
    starts = DateTime.new!(~D[2099-07-18], ~T[14:00:00], "Etc/UTC")
    ends = DateTime.new!(~D[2099-07-21], ~T[22:00:00], "Etc/UTC")
    event_fixture(%{title: "Schützenfest 2099", starts_at: starts, ends_at: ends})
    article_fixture(%{title: "Ein Homepage-Artikel"})
    throne_fixture(%{begin_year: 2098, end_year: 2099, king: "Hans Hansen"})

    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "Schützenfest 2099"
    # Event date badge (redesign): month abbreviation + link to the event.
    assert html =~ "Jul"
    assert html =~ "/termine/2099/"
    assert html =~ "Ein Homepage-Artikel"
    assert html =~ "König"
    assert html =~ "2098–2099"
    assert html =~ "Hans Hansen"
  end

  test "GET / links a throne to its article", %{conn: conn} do
    article = article_fixture(slug: "koenigsschiessen", date_published: ~U[2025-07-20 18:00:00Z])
    throne_fixture(article: article, begin_year: 2098, end_year: 2099, king: "Hans Hansen")

    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ ~s(href="/aktuell/2025/koenigsschiessen")
    assert html =~ "Zum Artikel →"
  end

  test "GET / does not link a „Nur Thron-Anzeige“ throne", %{conn: conn} do
    throne_fixture(begin_year: 2098, end_year: 2099, king: "Hans Hansen")

    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "Hans Hansen"
    refute html =~ "Zum Artikel →"
  end

  describe "month_abbr/1" do
    test "returns the short German month label for the date badge" do
      assert PageHTML.month_abbr(DateTime.new!(~D[2026-01-18], ~T[14:00:00], "Etc/UTC")) == "Jan"
      assert PageHTML.month_abbr(DateTime.new!(~D[2026-03-18], ~T[14:00:00], "Etc/UTC")) == "Mär"
      assert PageHTML.month_abbr(DateTime.new!(~D[2026-07-18], ~T[14:00:00], "Etc/UTC")) == "Jul"
      assert PageHTML.month_abbr(DateTime.new!(~D[2026-12-18], ~T[14:00:00], "Etc/UTC")) == "Dez"
    end
  end

  describe "countdown_target/1" do
    test "renders a naive ISO timestamp (no timezone) for the JS countdown" do
      dt = DateTime.new!(~D[2026-07-18], ~T[14:05:00], "Etc/UTC")
      assert PageHTML.countdown_target(dt) == "2026-07-18T14:05:00"
    end
  end

  describe "countdown_visible?/1" do
    defp in_days(offset) do
      Bbh.Time.now() |> DateTime.add(offset, :day)
    end

    test "shows for an upcoming event within the lead window" do
      assert PageHTML.countdown_visible?(%{
               show_countdown: true,
               countdown_lead_days: 60,
               starts_at: in_days(3)
             })
    end

    test "hides once the event has started (nothing left to count down)" do
      refute PageHTML.countdown_visible?(%{
               show_countdown: true,
               countdown_lead_days: 60,
               starts_at: in_days(-1)
             })
    end

    test "hides when the event is beyond the lead window" do
      refute PageHTML.countdown_visible?(%{
               show_countdown: true,
               countdown_lead_days: 30,
               starts_at: in_days(45)
             })
    end

    test "hides when disabled for the event" do
      refute PageHTML.countdown_visible?(%{
               show_countdown: false,
               countdown_lead_days: 60,
               starts_at: in_days(3)
             })
    end
  end

  describe "next_child_shown?/2" do
    test "only within 48 hours of the item's start, or while it runs" do
      item = %{starts_at: ~U[2030-07-20 14:00:00Z]}

      refute PageHTML.next_child_shown?(item, ~U[2030-07-10 12:00:00Z])
      refute PageHTML.next_child_shown?(item, ~U[2030-07-18 14:00:00Z])
      assert PageHTML.next_child_shown?(item, ~U[2030-07-18 14:01:00Z])
      assert PageHTML.next_child_shown?(item, ~U[2030-07-20 15:00:00Z])
    end
  end

  describe "countdown/4 for a festival" do
    defp fest_at(attrs \\ %{}) do
      Map.merge(
        %{
          show_countdown: true,
          countdown_lead_days: 60,
          all_day: true,
          starts_at: ~U[2030-07-20 00:00:00Z]
        },
        attrs
      )
    end

    defp item(starts_at), do: %{starts_at: starts_at}

    @first ~U[2030-07-20 14:00:00Z]

    test "before the festival: its first item, not the all-day 00:00" do
      assert %{at: @first, label: "Es beginnt in"} =
               PageHTML.countdown(fest_at(), item(@first), item(@first), ~U[2030-07-10 12:00:00Z])

      # also on the first day, before the first item
      assert %{at: @first, label: "Es beginnt in"} =
               PageHTML.countdown(fest_at(), item(@first), item(@first), ~U[2030-07-20 09:00:00Z])
    end

    test "a festival start with a real time counts when it is earlier" do
      fest = fest_at(%{starts_at: ~U[2030-07-20 13:00:00Z]})

      assert %{at: ~U[2030-07-20 13:00:00Z]} =
               PageHTML.countdown(fest, item(@first), item(@first), ~U[2030-07-10 12:00:00Z])

      later = fest_at(%{starts_at: ~U[2030-07-20 15:00:00Z]})

      assert %{at: @first} =
               PageHTML.countdown(later, item(@first), item(@first), ~U[2030-07-10 12:00:00Z])
    end

    test "during a running item: the one after it" do
      after_it = item(~U[2030-07-21 10:30:00Z])

      assert %{at: ~U[2030-07-21 10:30:00Z], label: "Nächster Programmpunkt in"} =
               PageHTML.countdown(fest_at(), item(@first), after_it, ~U[2030-07-21 10:00:00Z])
    end

    test "with nothing left to start: no countdown" do
      assert PageHTML.countdown(fest_at(), item(@first), nil, ~U[2030-07-23 21:00:00Z]) == nil
    end

    test "the festival's own switch and lead window still apply" do
      next = item(~U[2030-07-21 14:15:00Z])

      assert PageHTML.countdown(
               fest_at(%{show_countdown: false}),
               item(@first),
               next,
               ~U[2030-07-21 13:00:00Z]
             ) ==
               nil

      assert PageHTML.countdown(fest_at(), item(@first), item(@first), ~U[2030-01-01 00:00:00Z]) ==
               nil
    end

    test "an event without a programme counts down to its own start" do
      event = fest_at(%{all_day: false, starts_at: ~U[2030-07-20 14:00:00Z]})

      assert %{at: ~U[2030-07-20 14:00:00Z], label: "Es beginnt in"} =
               PageHTML.countdown(event, nil, nil, ~U[2030-07-10 12:00:00Z])

      assert PageHTML.countdown(event, nil, nil, ~U[2030-07-20 15:00:00Z]) == nil
      assert PageHTML.countdown(nil, nil, nil, ~U[2030-07-20 15:00:00Z]) == nil
    end
  end

  test "GET / shows a festival's running item and counts down to the next", %{conn: conn} do
    now = Bbh.Time.now() |> DateTime.truncate(:second) |> Map.put(:second, 0)
    today = DateTime.to_date(now)
    at = fn date -> DateTime.new!(date, ~T[00:00:00], "Etc/UTC") end

    fest =
      festival_fixture(%{
        title: "Schützenfest jetzt",
        starts_at: at.(Date.add(today, -1)),
        ends_at: at.(Date.add(today, 2))
      })

    programme_item_fixture(fest, %{
      title: "Frühschoppen",
      slug: "fruehschoppen",
      starts_at: DateTime.add(now, -30, :minute),
      ends_at: DateTime.add(now, 30, :minute)
    })

    next_start = DateTime.add(now, 2, :hour)

    programme_item_fixture(fest, %{
      title: "Festumzug",
      slug: "festumzug",
      starts_at: next_start,
      ends_at: DateTime.add(now, 3, :hour)
    })

    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "Schützenfest jetzt"
    assert html =~ ~s(href="/termine/#{fest.year}/#{fest.slug}#fruehschoppen")
    assert html =~ "Jetzt"
    assert html =~ "Frühschoppen"
    assert html =~ "Nächster Programmpunkt in"
    assert html =~ ~s(data-countdown-to="#{PageHTML.countdown_target(next_start)}")
    assert html =~ "data-countdown-now="
  end

  test "renders the home notice as (sanitized) HTML", %{conn: conn} do
    {:ok, _} =
      Bbh.Settings.update(%{
        "home_notice_enabled" => true,
        "home_notice_text" => "<p><strong>Achtung</strong></p><script>alert(1)</script>"
      })

    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "<strong>Achtung</strong>"
    refute html =~ "<script>alert"
  end
end
