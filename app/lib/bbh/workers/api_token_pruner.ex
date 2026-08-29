defmodule Bbh.Workers.ApiTokenPruner do
  @moduledoc """
  Deletes API tokens that expired or were revoked more than a month ago.

  Nightly rather than hourly: an expired token already fails `Bbh.ApiTokens.verify/2`, so
  this only reclaims rows. The month of grace keeps `last_used_at` readable after a
  revocation, which is exactly when someone wants to know where a leaked token was used.

  Self-healing like the other cron workers — the sweep is a plain delete over a window, so
  a missed run is fully repaired by the next one.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    case Bbh.ApiTokens.prune() do
      0 -> :ok
      count -> Logger.info("Pruned #{count} expired or revoked API token(s)")
    end

    :ok
  end
end
