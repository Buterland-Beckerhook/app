defmodule BbhWeb.Admin.EventLiveTest do
  use BbhWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Bbh.CalendarFixtures

  alias Bbh.Calendar

  setup :register_and_log_in_admin

  describe "Index" do
    test "lists events with their location", %{conn: conn} do
      location = location_fixture(name: "Vereinsheim")
      event = event_fixture(title: "Generalversammlung", location_id: location.id)

      {:ok, _lv, html} = live(conn, ~p"/admin/termine")
      assert html =~ event.title
      assert html =~ "Vereinsheim"
    end

    test "filters events by calendar", %{conn: conn} do
      _public = event_fixture(title: "Sommerfest")
      _internal = event_fixture(title: "Vorstandssitzung", calendar: "vorstand")

      {:ok, lv, html} = live(conn, ~p"/admin/termine")
      assert html =~ "Sommerfest"
      assert html =~ "Vorstandssitzung"

      html = lv |> form("form[phx-change=list-filter-cat]", %{cat: "vorstand"}) |> render_change()
      assert html =~ "Vorstandssitzung"
      refute html =~ "Sommerfest"

      html = lv |> form("form[phx-change=list-filter-cat]", %{cat: "public"}) |> render_change()
      assert html =~ "Sommerfest"
      refute html =~ "Vorstandssitzung"
    end

    test "deletes an event from the edit page with slug confirmation", %{conn: conn} do
      event = event_fixture()
      {:ok, lv, _html} = live(conn, ~p"/admin/termine/#{event.id}/bearbeiten")

      {:ok, _lv, html} =
        lv
        |> form("form[phx-submit=delete]", confirm: event.slug)
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/termine")

      assert html =~ "Termin gelöscht"
      assert_raise Ecto.NoResultsError, fn -> Calendar.get_event!(event.id) end
    end

    test "rejects deletion when the confirmation slug does not match", %{conn: conn} do
      event = event_fixture()
      {:ok, lv, _html} = live(conn, ~p"/admin/termine/#{event.id}/bearbeiten")

      html =
        lv
        |> form("form[phx-submit=delete]", confirm: "falsch")
        |> render_submit()

      assert html =~ "stimmt nicht überein"
      assert Calendar.get_event!(event.id)
    end
  end

  describe "Form (new)" do
    test "wires slug auto-generation from the title input", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/termine/neu")
      # The client-side hook (SlugFromTitle) fills the slug from the title; here we
      # only guard that it stays wired to a title input with a slug target present.
      assert has_element?(lv, "#event_title[phx-hook='SlugFromTitle']")
      assert has_element?(lv, "#event_slug")
    end

    test "creates an event and redirects", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/termine/neu")

      {:ok, _lv, html} =
        lv
        |> form("#event-form",
          event: %{
            title: "Herbstschießen",
            slug: "herbstschiessen",
            starts_at: "2027-09-01T18:00"
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/termine")

      assert html =~ "Termin erstellt"
      assert html =~ "Herbstschießen"
    end

    test "re-renders with an error when required fields are missing", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/termine/neu")

      html =
        lv
        |> form("#event-form", event: %{title: "", slug: "", starts_at: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank" or html =~ "wird benötigt" or html =~ "erforderlich"
    end
  end

  describe "Form (edit) — Ansehen" do
    test "links a public event to its page", %{conn: conn} do
      event = event_fixture()
      {:ok, view, _html} = live(conn, ~p"/admin/termine/#{event.id}/bearbeiten")

      assert view
             |> element(~s(a[target="_blank"][href="/termine/#{event.year}/#{event.slug}"]))
             |> render() =~ "Ansehen"
    end

    test "links a programme item to its anchor on the festival page", %{conn: conn} do
      festival = festival_fixture()
      item = programme_item_fixture(festival)
      {:ok, view, _html} = live(conn, ~p"/admin/termine/#{item.id}/bearbeiten")

      assert has_element?(
               view,
               ~s(a[href="/termine/#{festival.year}/#{festival.slug}##{item.slug}"]),
               "Ansehen"
             )
    end

    test "offers nothing to view while the event is a draft", %{conn: conn} do
      event = event_fixture(status: "draft")
      {:ok, _view, html} = live(conn, ~p"/admin/termine/#{event.id}/bearbeiten")
      refute html =~ "Ansehen"
    end
  end

  describe "plain (magic-link) session" do
    setup %{conn: _conn} do
      admin = Bbh.AccountsFixtures.admin_user_fixture()
      %{conn: log_in_user(build_conn(), admin, auth_method: "magic_link")}
    end

    test "edits internal events but not public ones", %{conn: conn} do
      public = event_fixture(title: "Sommerfest")
      internal = event_fixture(title: "Vorstandssitzung", calendar: "vorstand")

      assert {:ok, _lv, _html} = live(conn, ~p"/admin/termine/#{internal.id}/bearbeiten")

      assert {:error, {:live_redirect, %{to: "/admin/termine"}}} =
               live(conn, ~p"/admin/termine/#{public.id}/bearbeiten")
    end

    test "is not offered the public calendar for a new event", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/admin/termine/neu")
      refute html =~ "Öffentlich</option>"
    end
  end
end
