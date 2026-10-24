defmodule BbhWeb.LocationMapTest do
  # Not async: the map directory is application config.
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest
  import Bbh.MapFixtures
  import BbhWeb.SiteComponents

  alias Bbh.Calendar.Location

  @platz %Location{name: "Schützenplatz", lat: 52.2063619, lng: 7.0017587}

  setup do
    with_map_dir()
    :ok
  end

  test "renders a hidden map figure for a covered location" do
    write_pmtiles(Bbh.Map.target_path(), bbox: {6.94, 52.13, 7.11, 52.27})
    html = render_component(&location_map/1, location: @platz, nonce: "n0nce")

    assert html =~ ~r/<figure[^>]* hidden/
    assert html =~ ~s(data-lat="52.2063619")
    assert html =~ ~s(data-lng="7.0017587")
    assert html =~ ~s(data-bounds="6.94,52.13,7.11,52.27")
    assert html =~ ~r{data-tiles-url="/karte/region.pmtiles\?v=[^"]+"}
    assert html =~ ~s(aria-label="Karte: Schützenplatz")
    assert html =~ "OpenStreetMap-Mitwirkende"
    assert html =~ ~s(<script type="module" nonce="n0nce" src="/assets/map/map.js">)
  end

  test "renders nothing without an archive" do
    assert render_component(&location_map/1, location: @platz) |> String.trim() == ""
  end

  test "renders nothing for a location outside the archive or without coordinates" do
    write_pmtiles(Bbh.Map.target_path(), bbox: {6.94, 52.13, 7.11, 52.27})

    for location <- [%Location{name: "München", lat: 48.137, lng: 11.575}, %Location{name: "?"}] do
      assert render_component(&location_map/1, location: location) |> String.trim() == ""
    end
  end
end
