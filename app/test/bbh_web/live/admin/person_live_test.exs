defmodule BbhWeb.Admin.PersonLiveTest do
  use BbhWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Bbh.ClubFixtures

  alias Bbh.Club

  setup :register_and_log_in_admin

  describe "Index" do
    test "lists people", %{conn: conn} do
      person = person_fixture(name: "Anna Beispiel")
      {:ok, _lv, html} = live(conn, ~p"/admin/personen")

      assert html =~ "Personen"
      assert html =~ person.name
    end

    test "deletes a person", %{conn: conn} do
      person = person_fixture()
      {:ok, lv, _html} = live(conn, ~p"/admin/personen")

      render_click(lv, "delete", %{"id" => person.id})
      assert_raise Ecto.NoResultsError, fn -> Club.get_person!(person.id) end
    end
  end

  describe "Form (new)" do
    test "creates a person and redirects", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/personen/neu")

      {:ok, _lv, html} =
        lv
        |> form("#person-form", person: %{name: "Klaus Vorstand", role: "vorstand"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/personen")

      assert html =~ "Klaus Vorstand"
    end
  end
end
