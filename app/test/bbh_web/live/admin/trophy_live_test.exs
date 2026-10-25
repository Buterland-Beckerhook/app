defmodule BbhWeb.Admin.TrophyLiveTest do
  use BbhWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Bbh.ClubFixtures

  alias Bbh.Club

  setup :register_and_log_in_admin

  test "lists trophies and winners", %{conn: conn} do
    trophy = trophy_fixture(name: "Königspokal", since: 1996)
    trophy_win_fixture(trophy: trophy, year: 2025, winner: "Michael Terhalle", rings: 28)

    {:ok, _lv, html} = live(conn, ~p"/admin/pokale")

    assert html =~ "Königspokal"
    assert html =~ "seit 1996"
    assert html =~ "Michael Terhalle"
    assert html =~ "28"
  end

  test "enters a winner, preselecting the trophy from the link", %{conn: conn} do
    trophy = trophy_fixture(name: "Schützenpokal")
    {:ok, lv, html} = live(conn, ~p"/admin/pokale/sieger/neu?pokal=#{trophy.id}")

    selected = html |> LazyHTML.from_document() |> LazyHTML.query("option[selected]")
    assert LazyHTML.attribute(selected, "value") == [trophy.id]

    {:ok, _lv, html} =
      lv
      |> form("#trophy-win-form",
        trophy_win: %{trophy_id: trophy.id, year: 2026, winner: "Simon Sell", rings: 29}
      )
      |> render_submit()
      |> follow_redirect(conn, ~p"/admin/pokale")

    assert html =~ "Sieger gespeichert"
    assert [%{winner: "Simon Sell", rings: 29, year: 2026}] = Club.list_trophy_wins()
  end

  test "a second winner for the same trophy and year is refused", %{conn: conn} do
    trophy = trophy_fixture()
    trophy_win_fixture(trophy: trophy, year: 2026)
    {:ok, lv, _html} = live(conn, ~p"/admin/pokale/sieger/neu")

    html =
      lv
      |> form("#trophy-win-form", trophy_win: %{trophy_id: trophy.id, year: 2026, winner: "X"})
      |> render_submit()

    assert html =~ "schon ein Sieger eingetragen"
  end

  test "creates a trophy", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/pokale/neu")

    {:ok, _lv, html} =
      lv
      |> form("#trophy-form", trophy: %{name: "Damenpokal", since: 2027})
      |> render_submit()
      |> follow_redirect(conn, ~p"/admin/pokale")

    assert html =~ "Damenpokal"
  end

  test "refuses to delete a trophy that has winners", %{conn: conn} do
    trophy = trophy_fixture(name: "Biwakpokal")
    trophy_win_fixture(trophy: trophy)
    {:ok, lv, _html} = live(conn, ~p"/admin/pokale/#{trophy.id}/bearbeiten")

    html = lv |> form("form[phx-submit=delete]", confirm: "Biwakpokal") |> render_submit()

    assert html =~ "erst die Sieger löschen"
    assert Club.get_trophy!(trophy.id)
  end
end
