defmodule Mix.Tasks.Bbh.Map.Update do
  @shortdoc "Fetch the regional map archive now (Protomaps build → priv/tiles)"
  @moduledoc """
  Extract the map archive for the current locations right away, instead of waiting
  for the boot or monthly trigger (`Bbh.Workers.MapTilesUpdater`, ADR 0014).

      mix bbh.map.update

  Needs the `pmtiles` CLI on the PATH (the dev and production images ship it). On
  the server, enqueue the same job in the running release instead:

      bin/bbh rpc "Bbh.Map.enqueue_update()"
  """
  use Mix.Task

  @requirements ["app.start"]

  @impl true
  def run(_args) do
    case Bbh.Workers.MapTilesUpdater.run() do
      :ok -> Mix.shell().info("Map archive updated: #{Bbh.Map.target_path()}")
      other -> Mix.raise("Map archive not updated: #{inspect(other)}")
    end
  end
end
