defmodule BbhWeb.PageContentControllerTest do
  use BbhWeb.ConnCase, async: true

  import Bbh.ContentFixtures
  import Bbh.ClubFixtures

  test "GET /verein renders", %{conn: conn} do
    assert conn |> get(~p"/verein") |> html_response(200) =~ "Verein"
  end

  test "GET /verein/vorstand lists board members", %{conn: conn} do
    person = person_fixture(name: "Vorstandsmitglied", role: "vorstand")
    html = conn |> get(~p"/verein/vorstand") |> html_response(200)
    assert html =~ person.name
  end

  test "GET /verein/:slug renders a published page", %{conn: conn} do
    page_fixture(slug: "mitglied-werden", title: "Mitglied werden", status: "published")
    html = conn |> get(~p"/verein/mitglied-werden") |> html_response(200)
    assert html =~ "Mitglied werden"
  end

  test "GET /verein/:slug returns 404 for an unknown page with no people", %{conn: conn} do
    assert conn |> get(~p"/verein/gibt-es-nicht") |> response(404)
  end

  test "GET /impressum renders", %{conn: conn} do
    page_fixture(slug: "impressum", title: "Impressum", status: "published")
    assert conn |> get(~p"/impressum") |> html_response(200) =~ "Impressum"
  end
end
