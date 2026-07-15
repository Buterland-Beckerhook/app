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
  end

  test "GET / renders event banner, articles and throne when data exists", %{conn: conn} do
    starts = DateTime.new!(~D[2099-07-18], ~T[14:00:00], "Etc/UTC")
    ends = DateTime.new!(~D[2099-07-21], ~T[22:00:00], "Etc/UTC")
    event_fixture(%{title: "Schützenfest 2099", starts_at: starts, ends_at: ends})
    article_fixture(%{title: "Ein Homepage-Artikel"})
    throne_fixture(%{begin_year: 2098, end_year: 2099, king: "Hans Hansen"})

    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "Schützenfest 2099"
    assert html =~ "–21 · 2099"
    assert html =~ "Ein Homepage-Artikel"
    assert html =~ "König 2098–2099"
    assert html =~ "Amtierend"
    assert html =~ "Hans Hansen"
  end

  describe "badge_suffix/1" do
    test "appends the end day for multi-day events within one month" do
      event = %{
        starts_at: DateTime.new!(~D[2026-07-18], ~T[14:00:00], "Etc/UTC"),
        ends_at: DateTime.new!(~D[2026-07-21], ~T[22:00:00], "Etc/UTC")
      }

      assert PageHTML.badge_suffix(event) == "–21 · 2026"
    end

    test "shows only the year without an end date" do
      event = %{starts_at: DateTime.new!(~D[2026-07-18], ~T[14:00:00], "Etc/UTC"), ends_at: nil}
      assert PageHTML.badge_suffix(event) == "2026"
    end

    test "shows only the year for a same-day event" do
      event = %{
        starts_at: DateTime.new!(~D[2026-07-18], ~T[14:00:00], "Etc/UTC"),
        ends_at: DateTime.new!(~D[2026-07-18], ~T[22:00:00], "Etc/UTC")
      }

      assert PageHTML.badge_suffix(event) == "2026"
    end

    test "falls back to the year for cross-month ranges" do
      event = %{
        starts_at: DateTime.new!(~D[2026-07-31], ~T[14:00:00], "Etc/UTC"),
        ends_at: DateTime.new!(~D[2026-08-02], ~T[22:00:00], "Etc/UTC")
      }

      assert PageHTML.badge_suffix(event) == "2026"
    end
  end
end
