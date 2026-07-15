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
end
