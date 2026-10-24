defmodule Bbh.Workers.AnalyticsRollup do
  @moduledoc """
  Nightly: replaces the per-visitor hashes of every day past the retention window with
  that day's totals (`Bbh.Analytics.roll_up/1`), so pseudonymous hashes live at most
  seven days while the dashboard keeps its history.

  Self-healing like the other cron workers — it always works on "everything older than
  the window", so a missed night is simply caught up by the next run.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    {:ok, %{visitors: visitors, ical: ical}} = Bbh.Analytics.roll_up()

    if visitors + ical > 0,
      do:
        Logger.info(
          "Rolled up #{visitors} visitor and #{ical} iCal hash row(s) into daily totals"
        )

    :ok
  end
end
