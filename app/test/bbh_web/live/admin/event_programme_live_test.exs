defmodule BbhWeb.Admin.EventProgrammeLiveTest do
  @moduledoc "Admin UX for festivals and their programme items."
  use BbhWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Bbh.CalendarFixtures

  alias Bbh.Calendar
  alias Bbh.Calendar.Event

  setup :register_and_log_in_admin

  setup do
    fest = festival_fixture(title: "Schützenfest 2030")
    %{fest: fest}
  end

  describe "adding a programme item" do
    test "the festival's button prefills an item and saving returns to the festival", %{
      conn: conn,
      fest: fest
    } do
      {:ok, lv, html} = live(conn, ~p"/admin/termine/neu?parent=#{fest.id}")

      assert html =~ "Programmpunkt von"

      assert has_element?(
               lv,
               "select[name='event[parent_id]'] option[selected][value='#{fest.id}']"
             )

      # Inherited from the festival, so not offered.
      refute html =~ "Ganztägig (im Kalender-Export"
      refute html =~ "Countdown anzeigen"
      refute html =~ ~s(name="event[calendar]")
      # Reminders stay possible for single items.
      assert html =~ "Erinnerungen (Push)"

      {:ok, _lv, html} =
        lv
        |> form("#event-form",
          event: %{
            title: "Gottesdienst",
            slug: "gottesdienst",
            starts_at: "2030-07-21T09:30",
            ends_at: "2030-07-21T10:30"
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/termine/#{fest.id}/bearbeiten")

      assert html =~ "Termin erstellt"
      assert html =~ "Gottesdienst"
      assert [%Event{title: "Gottesdienst", parent_id: parent_id}] = Calendar.list_children(fest)
      assert parent_id == fest.id
    end

    test "an item outside the festival is rejected in the form", %{conn: conn, fest: fest} do
      {:ok, lv, _html} = live(conn, ~p"/admin/termine/neu?parent=#{fest.id}")

      html =
        lv
        |> form("#event-form",
          event: %{
            title: "Zu spät",
            slug: "zu-spaet",
            starts_at: "2030-07-24T20:00",
            ends_at: "2030-07-24T23:00"
          }
        )
        |> render_submit()

      assert html =~ "liegt nach dem Ende des Festes"
      assert Calendar.list_children(fest) == []
    end

    test "?parent= is ignored unless it names a festival", %{conn: conn} do
      plain = event_fixture(title: "Biwak")
      {:ok, _lv, html} = live(conn, ~p"/admin/termine/neu?parent=#{plain.id}")

      refute html =~ "Programmpunkt von"
      assert html =~ "Countdown anzeigen"
    end
  end

  describe "a festival's form" do
    test "lists its programme and warns that deleting takes it along", %{conn: conn, fest: fest} do
      item = programme_item_fixture(fest, title: "Königsschießen")

      {:ok, _lv, html} = live(conn, ~p"/admin/termine/#{fest.id}/bearbeiten")

      assert html =~ "Programm"
      assert html =~ "Königsschießen"
      assert html =~ ~s(href="/admin/termine/#{item.id}/bearbeiten")
      assert html =~ ~s(href="/admin/termine/neu?parent=#{fest.id}")
      assert html =~ "Löscht auch 1 Programmpunkt."
      # A festival with a programme cannot join another one.
      refute html =~ "Gehört zu"
    end

    test "an item's form links back to its festival", %{conn: conn, fest: fest} do
      item = programme_item_fixture(fest)
      {:ok, _lv, html} = live(conn, ~p"/admin/termine/#{item.id}/bearbeiten")

      assert html =~ "Programmpunkt von"
      assert html =~ ~s(href="/admin/termine/#{fest.id}/bearbeiten")
    end
  end

  describe "copying last year's programme" do
    setup %{fest: fest} do
      # Saturday 21 July 2029 — same weekday as the 2030 festival (Saturday 20 July).
      last_year =
        festival_fixture(
          title: "Schützenfest 2029",
          starts_at: ~U[2029-07-21 00:00:00Z],
          ends_at: ~U[2029-07-24 00:00:00Z]
        )

      programme_item_fixture(last_year,
        title: "Gottesdienst",
        slug: "gottesdienst",
        starts_at: ~U[2029-07-22 09:30:00Z],
        ends_at: ~U[2029-07-22 10:30:00Z],
        reminders: [%{lead_days: 1, text: "Morgen"}]
      )

      programme_item_fixture(last_year,
        title: "Kehraus",
        slug: "kehraus",
        status: "canceled",
        starts_at: ~U[2029-07-24 20:00:00Z],
        ends_at: ~U[2029-07-25 02:00:00Z]
      )

      %{fest: fest, last_year: last_year}
    end

    test "copies the items as drafts onto the same weekdays", %{
      conn: conn,
      fest: fest,
      last_year: last_year
    } do
      {:ok, lv, html} = live(conn, ~p"/admin/termine/#{fest.id}/bearbeiten")
      assert html =~ "Programm aus einem früheren Fest übernehmen"

      html = lv |> form("#copy-programme-form", source: last_year.id) |> render_submit()

      assert html =~ "2 Programmpunkte als Entwurf übernommen"
      refute html =~ "Programm aus einem früheren Fest übernehmen"

      assert [gottesdienst, kehraus] =
               fest |> Calendar.list_children() |> Bbh.Repo.preload(:reminders)

      assert gottesdienst.starts_at == ~U[2030-07-21 09:30:00Z]
      assert gottesdienst.status == "draft"
      assert gottesdienst.reminders == []
      assert kehraus.ends_at == ~U[2030-07-24 02:00:00Z]
      assert kehraus.status == "draft"
    end

    test "asks again when the weekdays differ", %{conn: conn, last_year: last_year} do
      # Sunday 21 July 2030
      sunday =
        festival_fixture(
          title: "Sonntagsfest",
          starts_at: ~U[2030-07-21 00:00:00Z],
          ends_at: ~U[2030-07-25 00:00:00Z]
        )

      {:ok, lv, _html} = live(conn, ~p"/admin/termine/#{sunday.id}/bearbeiten")

      html = lv |> form("#copy-programme-form", source: last_year.id) |> render_submit()
      assert html =~ "anderen Wochentag"
      assert Calendar.list_children(sunday) == []

      html = lv |> form("#copy-programme-confirm") |> render_submit()
      assert html =~ "2 Programmpunkte als Entwurf übernommen"
      assert length(Calendar.list_children(sunday)) == 2
    end

    test "copies nothing when an item does not fit", %{conn: conn, last_year: last_year} do
      short =
        festival_fixture(
          title: "Kurzes Fest",
          starts_at: ~U[2030-07-20 00:00:00Z],
          ends_at: ~U[2030-07-21 00:00:00Z]
        )

      {:ok, lv, _html} = live(conn, ~p"/admin/termine/#{short.id}/bearbeiten")
      html = lv |> form("#copy-programme-form", source: last_year.id) |> render_submit()

      assert html =~ "„Kehraus“ passt nicht ins Fest"
      assert Calendar.list_children(short) == []
    end
  end

  describe "index" do
    test "nests the programme under its festival, collapsed", %{conn: conn, fest: fest} do
      programme_item_fixture(fest, title: "Großer Festball")

      programme_item_fixture(fest,
        title: "Großes Wecken",
        starts_at: ~U[2030-07-22 06:00:00Z],
        ends_at: ~U[2030-07-22 10:30:00Z]
      )

      {:ok, lv, html} = live(conn, ~p"/admin/termine")

      assert html =~ "Schützenfest 2030"
      assert html =~ "2 Programmpunkte"
      refute html =~ "Großer Festball"

      html = lv |> element("button[phx-value-id='#{fest.id}']") |> render_click()
      assert html =~ "↳ Großer Festball"
      assert html =~ "↳ Großes Wecken"

      html = lv |> element("button[phx-value-id='#{fest.id}']") |> render_click()
      refute html =~ "Großer Festball"
    end

    test "a search for an item finds its festival", %{conn: conn, fest: fest} do
      programme_item_fixture(fest, title: "Großes Wecken")
      _other = event_fixture(title: "Biwak")
      {:ok, lv, _html} = live(conn, ~p"/admin/termine")

      html = lv |> form("form[phx-change=list-filter]", %{q: "Wecken"}) |> render_change()
      assert html =~ "Schützenfest 2030"
      refute html =~ "Biwak"
    end
  end
end
