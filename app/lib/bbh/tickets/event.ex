defmodule Bbh.Tickets.Event do
  @moduledoc """
  History and access log of the Postfach: who opened, took, changed or downloaded what.
  `meta` never carries personal data — statuses, queue keys, user ids only.
  """
  use Ecto.Schema

  @actions ~w(created viewed assigned status_changed queue_changed replied noted
              attachment_downloaded pdf_exported received marked_spam unmarked_spam deleted restored
              server_copy_removed grants_changed member_number_set purged requester_changed)

  def actions, do: @actions

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "ticket_events" do
    belongs_to :ticket, Bbh.Tickets.Ticket
    belongs_to :user, Bbh.Accounts.User
    field :ticket_number, :integer
    field :action, :string
    field :meta, :map, default: %{}

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
