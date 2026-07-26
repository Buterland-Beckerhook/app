defmodule BbhWeb.Api.BlzControllerTest do
  use BbhWeb.ConnCase, async: true

  test "GET /api/blz returns BIC and Kreditinstitut for a known IBAN", %{conn: conn} do
    body = conn |> get(~p"/api/blz?iban=DE89370400440532013000") |> json_response(200)
    assert body["bic"] == "COBADEFFXXX"
    assert body["kreditinstitut"] =~ "Commerzbank"
  end

  test "GET /api/blz returns an empty object for an unknown IBAN", %{conn: conn} do
    assert conn |> get(~p"/api/blz?iban=DE00999999990000000000") |> json_response(200) == %{}
  end

  test "GET /api/blz without an iban param returns an empty object", %{conn: conn} do
    assert conn |> get(~p"/api/blz") |> json_response(200) == %{}
  end
end
