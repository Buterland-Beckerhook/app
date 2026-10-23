defmodule Bbh.Workers.NotFoundPruner do
  @moduledoc """
  Nightly sweep of the 404 log (`not_found_paths`): drops paths not requested for 90
  days, so the list in `/admin/weiterleitungen` shows what is still being hit rather
  than every typo since the relaunch.

  Self-healing like the other cron workers — a plain delete over a window.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    count = Bbh.Redirects.prune_not_found(90)
    if count > 0, do: Logger.info("Pruned #{count} stale 404-log entr(y/ies)")
    :ok
  end
end
