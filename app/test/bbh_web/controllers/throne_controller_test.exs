defmodule BbhWeb.ThroneControllerTest do
  use BbhWeb.ConnCase, async: true

  import Bbh.ContentFixtures

  test "GET /thron lists thrones", %{conn: conn} do
    throne_fixture(king: "Friedrich der Erste")
    html = conn |> get(~p"/thron") |> html_response(200)

    assert html =~ "Throne" or html =~ "Thron"
    assert html =~ "Friedrich der Erste"
  end

  test "GET /thron renders with no thrones", %{conn: conn} do
    assert conn |> get(~p"/thron") |> html_response(200)
  end
end
