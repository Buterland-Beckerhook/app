defmodule Bbh.Map do
  @moduledoc """
  The self-hosted vector map behind the event location map: one regional PMTiles
  archive, extracted from the Protomaps daily build by `Bbh.Workers.MapTilesUpdater`
  and served from our own origin by `BbhWeb.Plugs.Map`. See
  `docs/adr/0014-self-hosted-osm-map.md`.

  Like `Bbh.Blz`, everything degrades gracefully: no archive, or a location outside
  it, simply means no embedded map — the event page keeps its address and its
  OpenStreetMap links. The archive is resolved in this order, first hit wins:

    1. `MAP_TILES_FILE` env var (an absolute path), if set and present. Pins the
       archive: the updater leaves it alone.
    2. `<dir>/region.pmtiles` — written by the updater (`/data/map` in production,
       inside the uploads volume).

  The archive's header (bounds, zooms) is read once and kept in `:persistent_term`,
  keyed by the file's size and mtime, so a swapped archive is picked up on the next
  read without any explicit invalidation.
  """
  import Ecto.Query

  alias Bbh.Calendar.Location
  alias Bbh.Repo

  @file_name "region.pmtiles"
  @pt_key {__MODULE__, :info}

  # The area the map always covers (Gronau and Epe), so the extract never collapses
  # onto a single location. {min_lon, min_lat, max_lon, max_lat}.
  @home_bbox {6.94, 52.13, 7.11, 52.27}
  # Room around each location, so its marker never sits on the edge of the map.
  @margin_km 3
  # Locations farther from home than this (an Ausflug) don't grow the extract — they
  # keep their links only, so one trip can't pull in half the country.
  @max_distance_km 50

  @km_per_degree 111.32

  @doc "Path of the archive to serve, or nil when there is none."
  def tiles_path do
    [System.get_env("MAP_TILES_FILE"), target_path()]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.find(&File.regular?/1)
  end

  @doc "Where the updater writes the archive."
  def target_path, do: Path.join(config(:dir), @file_name)

  @doc "Is the archive pinned by `MAP_TILES_FILE` (so the updater must not replace it)?"
  def pinned?, do: System.get_env("MAP_TILES_FILE") not in [nil, ""]

  @doc "Is there an archive to show a map from?"
  def available?, do: info() != nil

  @doc """
  The served archive: `%{path, bbox, min_zoom, max_zoom, version}`, or nil. `bbox` is
  `{min_lon, min_lat, max_lon, max_lat}`; `version` changes whenever the file does
  and busts browser caches (it rides on the tiles URL).
  """
  def info do
    with path when is_binary(path) <- tiles_path(),
         {:ok, %File.Stat{size: size, mtime: mtime}} <- File.stat(path, time: :posix) do
      key = {path, size, mtime}

      case :persistent_term.get(@pt_key, nil) do
        {^key, info} -> info
        _ -> cache(key, read_info(path, size, mtime))
      end
    else
      _ -> nil
    end
  end

  defp cache(key, info) do
    :persistent_term.put(@pt_key, {key, info})
    info
  end

  defp read_info(path, size, mtime) do
    case read_header(path) do
      {:ok, header} ->
        header
        |> Map.take([:bbox, :min_zoom, :max_zoom])
        |> Map.merge(%{path: path, version: "#{mtime}-#{size}"})

      {:error, _} ->
        nil
    end
  end

  @doc "Does the served archive cover this location? False without coordinates or archive."
  def covers?(%{lat: lat, lng: lng}) when is_number(lat) and is_number(lng) do
    case info() do
      %{bbox: bbox} -> inside?(bbox, lng, lat)
      nil -> false
    end
  end

  def covers?(_location), do: false

  defp inside?({min_lon, min_lat, max_lon, max_lat}, lng, lat),
    do: lng >= min_lon and lng <= max_lon and lat >= min_lat and lat <= max_lat

  @doc """
  The area the archive should cover: the home area plus every located venue within
  #{@max_distance_km} km of it, each with #{@margin_km} km of room. Rounded outwards
  to three decimals (~100 m) so the CLI argument stays stable.
  """
  def needed_bbox do
    Repo.all(
      from l in Location,
        where: not is_nil(l.lat) and not is_nil(l.lng),
        select: {l.lng, l.lat}
    )
    |> Enum.filter(fn {lng, lat} -> nearby?(lng, lat) end)
    |> Enum.reduce(@home_bbox, fn {lng, lat}, bbox -> merge_bbox(bbox, around(lng, lat)) end)
    |> round_out()
  end

  @doc "Would the archive grow to include this location (it is near enough)?"
  def wanted?(%{lat: lat, lng: lng}) when is_number(lat) and is_number(lng),
    do: nearby?(lng, lat)

  def wanted?(_location), do: false

  defp nearby?(lng, lat) do
    {min_lon, min_lat, max_lon, max_lat} = @home_bbox

    distance_km({(min_lon + max_lon) / 2, (min_lat + max_lat) / 2}, {lng, lat}) <=
      @max_distance_km
  end

  # Equirectangular approximation — plenty at this scale.
  defp distance_km({lng1, lat1}, {lng2, lat2}) do
    x = (lng2 - lng1) * :math.cos(deg_to_rad((lat1 + lat2) / 2))
    :math.sqrt(x * x + (lat2 - lat1) * (lat2 - lat1)) * @km_per_degree
  end

  defp around(lng, lat) do
    dlat = @margin_km / @km_per_degree
    dlng = @margin_km / (@km_per_degree * :math.cos(deg_to_rad(lat)))
    {lng - dlng, lat - dlat, lng + dlng, lat + dlat}
  end

  defp merge_bbox({a1, b1, c1, d1}, {a2, b2, c2, d2}),
    do: {min(a1, a2), min(b1, b2), max(c1, c2), max(d1, d2)}

  defp round_out({min_lon, min_lat, max_lon, max_lat}) do
    floor3 = &(Float.floor(&1 * 1000) / 1000)
    ceil3 = &(Float.ceil(&1 * 1000) / 1000)
    {floor3.(min_lon), floor3.(min_lat), ceil3.(max_lon), ceil3.(max_lat)}
  end

  defp deg_to_rad(deg), do: deg * :math.pi() / 180

  @doc """
  The tile schema major the vendored style (`@protomaps/basemaps` 5.x) renders. An
  archive of any other schema would draw wrongly, so the updater refuses it.
  """
  def tile_schema_major, do: 4

  @doc """
  Read a PMTiles v3 header (and its metadata) from `path`:
  `{:ok, %{bbox, min_zoom, max_zoom, metadata}}` or `{:error, reason}`.
  """
  # The path is the resolved archive (operator config or our own data dir), never
  # request input.
  # sobelow_skip ["Traversal.FileModule"]
  def read_header(path) do
    File.open(path, [:read, :binary], fn io ->
      with <<"PMTiles", 3, _root::binary-size(16), meta_offset::little-64, meta_length::little-64,
             _::binary-size(56), _clustered, internal_compression, _tile_compression, _tile_type,
             min_zoom, max_zoom, min_lon::little-signed-32, min_lat::little-signed-32,
             max_lon::little-signed-32, max_lat::little-signed-32, _rest::binary>> <-
             IO.binread(io, 127),
           {:ok, metadata} <- read_metadata(io, meta_offset, meta_length, internal_compression) do
        {:ok,
         %{
           bbox: {min_lon / 1.0e7, min_lat / 1.0e7, max_lon / 1.0e7, max_lat / 1.0e7},
           min_zoom: min_zoom,
           max_zoom: max_zoom,
           metadata: metadata
         }}
      else
        {:error, _} = error -> error
        _ -> {:error, :not_pmtiles}
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, _} = error -> error
    end
  end

  # Internal compression 1 = none, 2 = gzip; the Protomaps builds use gzip.
  defp read_metadata(io, offset, length, compression) do
    with {:ok, data} when byte_size(data) == length <- :file.pread(io, offset, length),
         {:ok, json} <- decompress(data, compression),
         {:ok, metadata} when is_map(metadata) <- Jason.decode(json) do
      {:ok, metadata}
    else
      _ -> {:error, :bad_metadata}
    end
  end

  defp decompress(data, 1), do: {:ok, data}

  defp decompress(data, 2) do
    {:ok, :zlib.gunzip(data)}
  rescue
    ErlangError -> {:error, :bad_metadata}
  end

  defp decompress(_data, _compression), do: {:error, :unsupported_compression}

  @doc "Enqueue a refresh of the archive (deduplicated by the worker's uniqueness)."
  def enqueue_update do
    if config(:auto_update), do: Oban.insert(Bbh.Workers.MapTilesUpdater.new(%{})), else: :ok
  end

  @doc """
  After boot: fetch an archive if there is none yet, so a fresh install (or a dev
  checkout) heals itself. Never raises — the site boots without a map.
  """
  def ensure_tiles do
    if config(:auto_update) and tiles_path() == nil, do: enqueue_update()
    :ok
  rescue
    _ -> :ok
  end

  @doc """
  After a location is saved: grow the archive when the location is wanted on the map
  but outside what it covers.
  """
  def location_changed(%Location{} = location) do
    if available?() and wanted?(location) and not covers?(location),
      do: enqueue_update()

    :ok
  end

  @doc false
  def config(key), do: Application.get_env(:bbh, __MODULE__, [])[key]
end
