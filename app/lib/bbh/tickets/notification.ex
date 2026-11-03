defmodule Bbh.Tickets.Notification do
  @moduledoc """
  Outbox row: this user still has to hear about this ticket (`Bbh.Tickets.Alerts`). Ids
  only — no personal data, like Oban args.
  """
  use Bbh.Schema

  schema "ticket_notifications" do
    belongs_to :user, Bbh.Accounts.User
    belongs_to :ticket, Bbh.Tickets.Ticket
    field :kind, :string

    timestamps(updated_at: false)
  end
end
