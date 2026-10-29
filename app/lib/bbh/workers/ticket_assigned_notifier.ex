defmodule Bbh.Workers.TicketAssignedNotifier do
  @moduledoc """
  Mails the new assignee when someone else assigned them a Postfach ticket. The job
  carries ids only — Oban args live in the database and its dumps.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias Bbh.Accounts
  alias Bbh.Repo
  alias Bbh.Tickets.{Notifier, Ticket}

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"ticket_id" => ticket_id, "assignee_id" => assignee_id, "by_id" => by_id}
      }) do
    with %Ticket{assignee_id: ^assignee_id, deleted_at: nil} = ticket <-
           Repo.get(Ticket, ticket_id),
         %{} = assignee <- Repo.get(Accounts.User, assignee_id),
         %{} = by <- Repo.get(Accounts.User, by_id) do
      Notifier.assigned(assignee, ticket, by)
    end

    # Reassigned again, deleted, or a user gone: nothing to say.
    :ok
  end
end
