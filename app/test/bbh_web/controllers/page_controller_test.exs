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
    # Event date badge (redesign): month abbreviation + link to the event.
    assert html =~ "Jul"
    assert html =~ "/termine/2099/"
    assert html =~ "Ein Homepage-Artikel"
    assert html =~ "König 2098–2099"
    assert html =~ "Amtierend"
    assert html =~ "Hans Hansen"
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
end
