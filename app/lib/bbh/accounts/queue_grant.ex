defmodule Bbh.Accounts.QueueGrant do
  @moduledoc """
  One user's access to one Postfach queue. A permission of the user, like
  `users.calendars`, so it lives with the accounts; what a queue *is* belongs to
  `Bbh.Tickets.Queue`, and granting goes through `Bbh.Tickets.Grants`, which checks the
  key against it.
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "queue_grants" do
    belongs_to :user, Bbh.Accounts.User
    belongs_to :granted_by, Bbh.Accounts.User
    field :queue_key, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
