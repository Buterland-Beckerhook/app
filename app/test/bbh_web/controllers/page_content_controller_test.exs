defmodule BbhWeb.PageContentControllerTest do
  use BbhWeb.ConnCase, async: true

  import Bbh.ContentFixtures
  import Bbh.ClubFixtures

  test "GET /verein lists published top-level pages", %{conn: conn} do
    page_fixture(slug: "ueber-uns", title: "Über uns", status: "published")
    html = conn |> get(~p"/verein") |> html_response(200)
    assert html =~ "Über uns"
    assert html =~ ~s(href="/verein/ueber-uns")
  end

  test "GET /verein/vorstand lists board members", %{conn: conn} do
    page_fixture(slug: "vorstand", title: "Vorstand", status: "published")
    person = person_fixture(name: "Vorstandsmitglied", role: "vorstand")
    html = conn |> get(~p"/verein/vorstand") |> html_response(200)
    assert html =~ person.name
  end

  test "GET a nested page renders with its breadcrumb chain", %{conn: conn} do
    parent = page_fixture(slug: "ueber-uns", title: "Über uns", status: "published")

    page_fixture(
      slug: "vereinsgeschichte",
      title: "Vereinsgeschichte",
      status: "published",
      parent_id: parent.id
    )

    html = conn |> get(~p"/verein/ueber-uns/vereinsgeschichte") |> html_response(200)
    assert html =~ "Vereinsgeschichte"
    assert html =~ "Über uns"
  end

  test "GET a child via its flat (non-canonical) path 301-redirects to the nested URL", %{
    conn: conn
  } do
    parent = page_fixture(slug: "ueber-uns", status: "published")
    page_fixture(slug: "vereinsgeschichte", status: "published", parent_id: parent.id)

    conn = get(conn, ~p"/verein/vereinsgeschichte")
    assert redirected_to(conn, 301) == "/verein/ueber-uns/vereinsgeschichte"
  end

  test "GET a top-level page renders", %{conn: conn} do
    page_fixture(slug: "mitglied-werden", title: "Mitglied werden", status: "published")
    html = conn |> get(~p"/verein/mitglied-werden") |> html_response(200)
    assert html =~ "Mitglied werden"
  end

  test "GET an unknown page returns 404", %{conn: conn} do
    assert conn |> get(~p"/verein/gibt-es-nicht") |> response(404)
  end

  test "GET /verein/impressum is not reachable (legal pages are excluded)", %{conn: conn} do
    page_fixture(slug: "impressum", title: "Impressum", status: "published", show_in_menu: false)
    assert conn |> get(~p"/verein/impressum") |> response(404)
  end

  test "GET /impressum renders", %{conn: conn} do
    page_fixture(slug: "impressum", title: "Impressum", status: "published")
    assert conn |> get(~p"/impressum") |> html_response(200) =~ "Impressum"
  end
end
