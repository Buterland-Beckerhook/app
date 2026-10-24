defmodule Bbh.MapTest do
  # Not async: the map directory is application config.
  use Bbh.DataCase, async: false
  use Oban.Testing, repo: Bbh.Repo

  import Bbh.CalendarFixtures
  import Bbh.MapFixtures

  alias Bbh.Calendar.Location
  alias Bbh.Workers.MapTilesUpdater

  setup do
    %{dir: with_map_dir()}
  end

  describe "read_header/1" do
    test "reads bounds, zooms and metadata", %{dir: dir} do
      path = write_pmtiles(Path.join(dir, "a.pmtiles"), bbox: {6.5, 52.0, 7.25, 52.5})

      assert {:ok, %{bbox: {6.5, 52.0, 7.25, 52.5}, min_zoom: 0, max_zoom: 15, metadata: meta}} =
               Bbh.Map.read_header(path)

      assert meta["version"] == "4.15.2"
    end

    test "rejects anything that isn't a PMTiles v3 archive", %{dir: dir} do
      path = Path.join(dir, "junk.pmtiles")
      File.mkdir_p!(dir)
      File.write!(path, "<html>404</html>")
      assert {:error, :not_pmtiles} = Bbh.Map.read_header(path)
      assert {:error, :enoent} = Bbh.Map.read_header(Path.join(dir, "missing"))
    end
  end

  describe "info/0" do
    test "is nil without an archive" do
      assert Bbh.Map.tiles_path() == nil
      assert Bbh.Map.info() == nil
      refute Bbh.Map.available?()
    end

    test "describes the archive in the map directory" do
      write_pmtiles(Bbh.Map.target_path(), bbox: {6.9, 52.1, 7.2, 52.3})

      assert %{bbox: {6.9, 52.1, 7.2, 52.3}, max_zoom: 15, version: version} = Bbh.Map.info()
      assert is_binary(version)
      assert Bbh.Map.available?()
    end

    test "picks up a swapped archive without restart" do
      write_pmtiles(Bbh.Map.target_path(), bbox: {6.9, 52.1, 7.2, 52.3})
      %{version: before} = Bbh.Map.info()

      write_pmtiles(Bbh.Map.target_path(), bbox: {6.0, 51.0, 8.0, 53.0}, padding: 1000)

      assert %{bbox: {6.0, 51.0, 8.0, 53.0}, version: later} = Bbh.Map.info()
      assert later != before
    end

    test "MAP_TILES_FILE wins and pins the archive", %{dir: dir} do
      write_pmtiles(Bbh.Map.target_path())
      pinned = write_pmtiles(Path.join(dir, "pinned.pmtiles"), bbox: {1.0, 2.0, 3.0, 4.0})
      System.put_env("MAP_TILES_FILE", pinned)
      on_exit(fn -> System.delete_env("MAP_TILES_FILE") end)

      assert Bbh.Map.tiles_path() == pinned
      assert Bbh.Map.pinned?()
      assert %{bbox: {1.0, 2.0, 3.0, 4.0}} = Bbh.Map.info()
    end
  end

  describe "covers?/1" do
    test "is true only for a located venue inside the archive" do
      write_pmtiles(Bbh.Map.target_path(), bbox: {6.9, 52.1, 7.2, 52.3})

      assert Bbh.Map.covers?(%Location{lat: 52.2, lng: 7.0})
      refute Bbh.Map.covers?(%Location{lat: 48.1, lng: 11.6})
      refute Bbh.Map.covers?(%Location{lat: nil, lng: nil})
    end

    test "is false without an archive" do
      refute Bbh.Map.covers?(%Location{lat: 52.2, lng: 7.0})
    end
  end

  describe "needed_bbox/0" do
    test "is the home area when no venue lies outside it" do
      location_fixture(lat: 52.2, lng: 7.0)
      assert Bbh.Map.needed_bbox() == {6.94, 52.13, 7.11, 52.27}
    end

    test "grows by the venue plus ~3 km of room" do
      # Ochtrup, ~15 km east of Gronau.
      location_fixture(lat: 52.21, lng: 7.19)
      {_, _, max_lon, max_lat} = Bbh.Map.needed_bbox()

      assert_in_delta max_lon, 7.19 + 3 / (111.32 * :math.cos(52.21 * :math.pi() / 180)), 0.002
      assert_in_delta max_lat, 52.27, 0.001
    end

    test "ignores venues far away (they keep their links only)" do
      location_fixture(lat: 48.137, lng: 11.575)
      assert Bbh.Map.needed_bbox() == {6.94, 52.13, 7.11, 52.27}
      refute Bbh.Map.wanted?(%Location{lat: 48.137, lng: 11.575})
    end
  end

  describe "location_changed/1" do
    setup do
      with_map_dir(auto_update: true)
      write_pmtiles(Bbh.Map.target_path(), bbox: {6.94, 52.13, 7.11, 52.27})
      :ok
    end

    test "a nearby venue outside the archive triggers an update" do
      location_fixture(lat: 52.21, lng: 7.19)
      assert_enqueued(worker: MapTilesUpdater)
    end

    test "a covered or far-away venue does not" do
      location_fixture(lat: 52.2, lng: 7.0)
      location_fixture(lat: 48.137, lng: 11.575)
      location_fixture()
      refute_enqueued(worker: MapTilesUpdater)
    end
  end

  describe "ensure_tiles/0" do
    test "fetches an archive when there is none" do
      with_map_dir(auto_update: true)
      Bbh.Map.ensure_tiles()
      assert_enqueued(worker: MapTilesUpdater)
    end

    test "does nothing when there is one, or when auto-update is off" do
      Bbh.Map.ensure_tiles()
      refute_enqueued(worker: MapTilesUpdater)

      with_map_dir(auto_update: true)
      write_pmtiles(Bbh.Map.target_path())
      Bbh.Map.ensure_tiles()
      refute_enqueued(worker: MapTilesUpdater)
    end
  end
end
