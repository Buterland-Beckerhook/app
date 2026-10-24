defmodule BbhWeb.EventHTMLTest do
  use ExUnit.Case, async: true

  alias Bbh.Calendar.Location
  alias BbhWeb.EventHTML

  describe "osm_url/1 and osm_route_url/1" do
    test "are nil without coordinates" do
      for loc <- [%Location{}, %Location{lat: 52.2}, %Location{lng: 7.0}] do
        assert EventHTML.osm_url(loc) == nil
        assert EventHTML.osm_route_url(loc) == nil
      end
    end

    test "mark the location on openstreetmap.org" do
      loc = %Location{lat: 52.2063619, lng: 7.0017587}

      assert EventHTML.osm_url(loc) ==
               "https://www.openstreetmap.org/?mlat=52.206362&mlon=7.001759#map=17/52.206362/7.001759"

      assert EventHTML.osm_route_url(loc) ==
               "https://www.openstreetmap.org/directions?to=52.206362%2C7.001759"
    end

    test "never use scientific notation" do
      loc = %Location{lat: 0.00001, lng: -1.0e-7}
      assert EventHTML.osm_route_url(loc) =~ "to=0.000010%2C-0.000000"
    end
  end
end
