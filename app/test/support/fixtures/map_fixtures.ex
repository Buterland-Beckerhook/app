defmodule Bbh.MapFixtures do
  @moduledoc "Test helpers for the map archive (`Bbh.Map`): a minimal PMTiles v3 file."

  @doc """
  Write a PMTiles v3 archive to `path`: a real header and gzipped metadata, then
  `padding` filler bytes standing in for tile data. Options: `:bbox`
  (`{min_lon, min_lat, max_lon, max_lat}`), `:version` (tile schema), `:padding`.
  """
  def write_pmtiles(path, opts \\ []) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, pmtiles(opts))
    path
  end

  def pmtiles(opts \\ []) do
    {min_lon, min_lat, max_lon, max_lat} = Keyword.get(opts, :bbox, {6.9, 52.1, 7.2, 52.3})
    metadata = :zlib.gzip(Jason.encode!(%{"version" => Keyword.get(opts, :version, "4.15.2")}))
    padding = :binary.copy(<<0>>, Keyword.get(opts, :padding, 200_000))
    e7 = &round(&1 * 1.0e7)

    header =
      <<"PMTiles", 3, 0::little-64, 0::little-64, 127::little-64, byte_size(metadata)::little-64,
        0::little-64, 0::little-64, 127 + byte_size(metadata)::little-64,
        byte_size(padding)::little-64, 0::little-64, 0::little-64, 0::little-64, 1, 2, 2, 1, 0,
        15, e7.(min_lon)::little-signed-32, e7.(min_lat)::little-signed-32,
        e7.(max_lon)::little-signed-32, e7.(max_lat)::little-signed-32, 0, 0::little-signed-32,
        0::little-signed-32>>

    127 = byte_size(header)
    header <> metadata <> padding
  end

  @doc "Point `Bbh.Map` at a fresh temporary directory for one test; restored on exit."
  def with_map_dir(extra_config \\ []) do
    dir = Path.join(System.tmp_dir!(), "bbh_map_#{System.unique_integer([:positive])}")
    original = Application.get_env(:bbh, Bbh.Map)
    Application.put_env(:bbh, Bbh.Map, Keyword.merge(original, [dir: dir] ++ extra_config))

    ExUnit.Callbacks.on_exit(fn ->
      Application.put_env(:bbh, Bbh.Map, original)
      File.rm_rf(dir)
    end)

    dir
  end
end
