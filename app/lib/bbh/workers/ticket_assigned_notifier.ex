defmodule Bbh.Workers.TicketAssignedNotifier do
  @moduledoc """
  Tells the new assignee when someone else assigned them a Postfach ticket, on their own
  channel; held back during quiet hours. The job carries ids only — Oban args live in
  the database and its dumps.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias Bbh.Tickets.Alerts

  @quiet_snooze_seconds 15 * 60

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"ticket_id" => ticket_id, "assignee_id" => assignee_id, "by_id" => by_id}
      }) do
    if Bbh.Settings.quiet_now?() do
      {:snooze, @quiet_snooze_seconds}
    else
      Alerts.assigned_by_ids(ticket_id, assignee_id, by_id)
    end
  end
end
