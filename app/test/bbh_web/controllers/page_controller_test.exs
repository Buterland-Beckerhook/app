defmodule BbhWeb.PageControllerTest do
  use BbhWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Willkommen"
  end
end
