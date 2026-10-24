defmodule BbhWeb.EventMapTest do
  # Not async: the map directory is application config.
  use BbhWeb.ConnCase, async: false

  import Bbh.CalendarFixtures
  import Bbh.MapFixtures

  test "the map comes last, after description and programme", %{conn: conn} do
    with_map_dir()
    write_pmtiles(Bbh.Map.target_path(), bbox: {6.9, 52.1, 7.2, 52.3})
    location = location_fixture(lat: 52.2063619, lng: 7.0017587)
    festival = festival_fixture(location_id: location.id, body: "<p>Beschreibungstext</p>")
    programme_item_fixture(festival, title: "Antreten")

    html =
      conn |> get(~p"/termine/#{festival.year}/#{festival.slug}") |> html_response(200)

    # The page itself — the JSON-LD above it names the programme too.
    [_head, page] = String.split(html, "<article", parts: 2)

    [address, body, programme, map] =
      Enum.map(
        ["Dorfstraße 1", "Beschreibungstext", "Antreten", "data-location-map"],
        &(:binary.match(page, &1) |> elem(0))
      )

    assert address < body and body < programme and programme < map
    assert page =~ "Anfahrt"
  end
end
