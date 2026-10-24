defmodule Bbh.Workers.MapTilesUpdaterTest do
  # Not async: map directory and the fake CLI's environment are global.
  use Bbh.DataCase, async: false

  # The failure paths log their warning on purpose.
  @moduletag :capture_log

  import Bbh.CalendarFixtures
  import Bbh.MapFixtures

  alias Bbh.Workers.MapTilesUpdater

  @fake_cli Path.expand("../../support/bin/fake_pmtiles", __DIR__)

  setup do
    dir = with_map_dir(pmtiles: @fake_cli, build_base_url: "https://build.test")
    source = write_pmtiles(Path.join(dir, "source/extract.pmtiles"), bbox: {6.9, 52.1, 7.2, 52.3})
    args_file = Path.join(dir, "args.txt")

    System.put_env("FAKE_PMTILES_SOURCE", source)
    System.put_env("FAKE_PMTILES_ARGS", args_file)

    on_exit(fn ->
      Enum.each(~w(FAKE_PMTILES_SOURCE FAKE_PMTILES_ARGS FAKE_PMTILES_FAIL), &System.delete_env/1)
    end)

    # Builds exist from two days back.
    Req.Test.stub(Bbh.Map, fn conn ->
      status =
        if conn.request_path in ["/20261022.pmtiles", "/20261021.pmtiles"], do: 200, else: 404

      Plug.Conn.send_resp(conn, status, "")
    end)

    %{dir: dir, source: source, args_file: args_file}
  end

  describe "latest_build/1" do
    test "is the newest build that exists" do
      assert MapTilesUpdater.latest_build(~D[2026-10-24]) ==
               {:ok, "https://build.test/20261022.pmtiles"}
    end

    test "gives up after the retention window" do
      assert MapTilesUpdater.latest_build(~D[2026-12-24]) == {:error, :no_build_found}
    end
  end

  describe "run/0" do
    test "extracts the needed area and swaps the archive in", %{args_file: args_file} do
      location_fixture(lat: 52.2, lng: 7.0)

      assert :ok = MapTilesUpdater.run()

      assert %{bbox: {6.9, 52.1, 7.2, 52.3}} = Bbh.Map.info()
      assert Bbh.Map.tiles_path() == Bbh.Map.target_path()

      [cmd, url, _tmp | flags] = args_file |> File.read!() |> String.split("\n", trim: true)
      assert cmd == "extract"
      assert url =~ ~r"^https://build\.test/\d{8}\.pmtiles$"
      assert "--bbox=6.94,52.13,7.11,52.27" in flags
      assert "--maxzoom=15" in flags
      assert leftovers() == []
    end

    test "a failed extract keeps the old archive" do
      old = write_pmtiles(Bbh.Map.target_path(), bbox: {1.0, 2.0, 3.0, 4.0})
      System.put_env("FAKE_PMTILES_FAIL", "1")

      assert {:error, {:extract_failed, 1, output}} = MapTilesUpdater.run()
      assert output =~ "404 Not Found"
      assert {:ok, %{bbox: {1.0, 2.0, 3.0, 4.0}}} = Bbh.Map.read_header(old)
      assert leftovers() == []
    end

    test "an archive of another tile schema is refused", %{source: source} do
      write_pmtiles(source, version: "5.0.0")
      assert {:error, {:schema_mismatch, 5}} = MapTilesUpdater.run()
      assert Bbh.Map.tiles_path() == nil
      assert leftovers() == []
    end

    test "a truncated archive is refused", %{source: source} do
      write_pmtiles(source, padding: 10)
      assert {:error, {:too_small, _}} = MapTilesUpdater.run()
      assert Bbh.Map.tiles_path() == nil
    end

    test "cancels without the CLI or with a pinned archive", %{source: source} do
      with_map_dir(pmtiles: "definitely-not-pmtiles")
      assert {:cancel, :no_cli} = MapTilesUpdater.run()

      System.put_env("MAP_TILES_FILE", source)
      on_exit(fn -> System.delete_env("MAP_TILES_FILE") end)
      assert {:cancel, :pinned} = MapTilesUpdater.run()
    end
  end

  defp leftovers do
    dir = Path.dirname(Bbh.Map.target_path())

    if File.dir?(dir),
      do: dir |> File.ls!() |> Enum.filter(&String.ends_with?(&1, ".tmp")),
      else: []
  end
end
