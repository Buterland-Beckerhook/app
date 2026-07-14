defmodule BbhWeb.Admin.LocationLiveTest do
  use BbhWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Bbh.CalendarFixtures

  alias Bbh.Calendar

  setup :register_and_log_in_admin

  describe "Index" do
    test "lists locations", %{conn: conn} do
      location = location_fixture(name: "Marktplatz", city: "Rheine")
      {:ok, _lv, html} = live(conn, ~p"/admin/orte")

      assert html =~ location.name
      assert html =~ "Rheine"
    end

    test "deletes a location", %{conn: conn} do
      location = location_fixture()
      {:ok, lv, _html} = live(conn, ~p"/admin/orte")

      render_click(lv, "delete", %{"id" => location.id})
      assert_raise Ecto.NoResultsError, fn -> Calendar.get_location!(location.id) end
    end
  end

  describe "Form (new)" do
    test "creates a location and redirects", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/orte/neu")

      {:ok, _lv, html} =
        lv
        |> form("#location-form",
          location: %{key: "halle", name: "Schützenhalle", city: "Rheine"}
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/orte")

      assert html =~ "Ort erstellt"
      assert html =~ "Schützenhalle"
    end

    test "validate surfaces an error for a blank required field", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/orte/neu")

      html =
        lv
        |> form("#location-form", location: %{key: "", name: ""})
        |> render_change()

      assert html =~ "can&#39;t be blank"
    end
  end
end
