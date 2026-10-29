defmodule Bbh.Workers.TicketPruner do
  @moduledoc """
  Nightly retention run of the Postfach (`Bbh.Tickets.Retention`). Self-healing like
  the other pruners: windows, not schedules, so a missed night is caught up by the next.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    counts = Bbh.Tickets.Retention.run()

    if Enum.any?(counts, fn {_, n} -> n > 0 end) do
      Logger.info("Postfach retention: #{inspect(counts)}")
    end

    :ok
  end
end
