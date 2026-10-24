defmodule Bbh.Workers.MapTilesUpdater do
  @moduledoc """
  Fetches the regional map archive (`Bbh.Map`): finds the newest Protomaps daily
  build, extracts `Bbh.Map.needed_bbox/0` from it with the `pmtiles` CLI (HTTP range
  requests — only the region is downloaded, ~10 MB), validates the result and swaps
  it in atomically. Any failure keeps the old archive.

  Runs monthly (cron), after boot when there is no archive yet, when a location is
  saved outside the covered area, and on demand (`mix bbh.map.update`, or
  `bin/bbh rpc "Bbh.Map.enqueue_update()"` on the server). Uniqueness collapses the
  triggers of one hour into a single extract.
  """
  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 3600]

  require Logger

  # The daily builds are retained for about a week; look back a little further.
  @lookback_days 10
  # An extract of the home area alone is ~10 MB; anything this small is broken.
  @min_size 100_000

  @impl Oban.Worker
  def perform(%Oban.Job{}), do: run()

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(20)

  @doc "Fetch and swap in a fresh archive now. `:ok`, `{:cancel, reason}` or `{:error, reason}`."
  def run do
    cond do
      Bbh.Map.pinned?() ->
        Logger.info("[map] MAP_TILES_FILE pins the archive — not updating")
        {:cancel, :pinned}

      System.find_executable(Bbh.Map.config(:pmtiles)) == nil ->
        Logger.warning("[map] pmtiles CLI not found — map archive not updated")
        {:cancel, :no_cli}

      true ->
        update()
    end
  end

  # Every path here derives from Bbh.Map's configured directory, never request input.
  # sobelow_skip ["Traversal.FileModule"]
  defp update do
    target = Bbh.Map.target_path()
    # Unique per run: a manual run may overlap the queued job.
    tmp = "#{target}.#{System.unique_integer([:positive])}.tmp"
    bbox = Bbh.Map.needed_bbox()

    with :ok <- File.mkdir_p(Path.dirname(target)),
         {:ok, build_url} <- latest_build(),
         :ok <- extract(build_url, tmp, bbox),
         :ok <- validate(tmp),
         :ok <- File.rename(tmp, target) do
      Logger.info("[map] archive updated from #{build_url}, bbox #{bbox_arg(bbox)}")
      :ok
    else
      error ->
        File.rm(tmp)
        Logger.warning("[map] archive not updated: #{inspect(error)}")
        error_tuple(error)
    end
  end

  defp error_tuple({:error, _} = error), do: error
  defp error_tuple(other), do: {:error, other}

  @doc false
  def latest_build(today \\ Date.utc_today()) do
    base = Bbh.Map.config(:build_base_url)

    1..@lookback_days
    |> Enum.map(&Date.add(today, -&1))
    |> Enum.find_value({:error, :no_build_found}, fn date ->
      url = "#{base}/#{Calendar.strftime(date, "%Y%m%d")}.pmtiles"

      case Req.head(url, req_options()) do
        {:ok, %Req.Response{status: 200}} -> {:ok, url}
        _ -> nil
      end
    end)
  end

  defp req_options,
    do: Keyword.merge([retry: false, receive_timeout: 15_000], Bbh.Map.config(:req_options) || [])

  # The executable is operator config and the arguments are our own: a URL built from
  # the configured base and a date, our temp path, and numbers. No shell is involved.
  # sobelow_skip ["CI.System"]
  defp extract(build_url, tmp, bbox) do
    args = [
      "extract",
      build_url,
      tmp,
      "--bbox=#{bbox_arg(bbox)}",
      "--maxzoom=#{Bbh.Map.config(:maxzoom)}"
    ]

    case System.cmd(Bbh.Map.config(:pmtiles), args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> {:error, {:extract_failed, status, tail(output)}}
    end
  end

  # The CLI draws a progress bar; the last few hundred bytes hold the error.
  defp tail(output), do: output |> String.slice(-500, 500) |> String.trim()

  defp bbox_arg({min_lon, min_lat, max_lon, max_lat}),
    do: Enum.map_join([min_lon, min_lat, max_lon, max_lat], ",", &Float.to_string/1)

  defp validate(path) do
    with {:ok, %File.Stat{size: size}} when size >= @min_size <- File.stat(path),
         {:ok, %{metadata: metadata}} <- Bbh.Map.read_header(path),
         {:ok, major} <- schema_major(metadata) do
      if major == Bbh.Map.tile_schema_major(),
        do: :ok,
        else: {:error, {:schema_mismatch, major}}
    else
      {:ok, %File.Stat{size: size}} -> {:error, {:too_small, size}}
      {:error, _} = error -> error
    end
  end

  defp schema_major(%{"version" => version}) when is_binary(version) do
    case Integer.parse(version) do
      {major, _} -> {:ok, major}
      :error -> {:error, {:bad_version, version}}
    end
  end

  defp schema_major(_metadata), do: {:error, :no_version}
end
