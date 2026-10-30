defmodule BbhWeb.Plugs.HealthTest do
  use BbhWeb.ConnCase, async: true

  test "liveness answers 200", %{conn: conn} do
    conn = get(conn, "/health/liveness")
    assert conn.halted
    assert text_response(conn, 200) == "OK"
  end

  test "readiness answers 200 while the database responds", %{conn: conn} do
    assert conn |> get("/health/readiness") |> text_response(200) == "OK"
  end

  test "other paths pass through untouched" do
    conn = Phoenix.ConnTest.build_conn(:get, "/kontakt")
    refute BbhWeb.Plugs.Health.call(conn, []).halted
  end
end
