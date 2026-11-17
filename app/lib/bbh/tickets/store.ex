defmodule Bbh.Tickets.Store do
  @moduledoc false
  # Shared by `Bbh.Tickets` and its sub-modules (`Replies`, `Requesters`, `Membership`):
  # the steps every write goes through — authorization, the encrypted message insert,
  # update-log-broadcast — so they live in one place instead of being copied.

  alias Bbh.Accounts.Scope
  alias Bbh.Authz
  alias Bbh.Repo
  alias Bbh.Tickets.{Message, ServerCopies, Ticket}
  alias Bbh.Vault

  @topic "tickets"

  def topic, do: @topic

  # Not to the writer itself: the ticket page reloads after its own action, and hearing
  # the same change again would load the whole ticket a second time.
  def broadcast(%Ticket{id: id}),
    do: Phoenix.PubSub.broadcast_from(Bbh.PubSub, self(), @topic, {:tickets_changed, id})

  def insert_message(%Ticket{id: ticket_id}, attrs) do
    %Message{}
    |> Message.changeset(Map.put(attrs, :ticket_id, ticket_id))
    |> Vault.encrypt_changes("ticket_messages", Message.encrypted_fields())
    |> Repo.insert()
  end

  # Working a ticket: queue access, and not deleted.
  def authorize(scope, ticket) do
    if Authz.can_handle_ticket?(scope, ticket) and is_nil(ticket.deleted_at),
      do: :ok,
      else: {:error, :unauthorized}
  end

  def authorize_view(scope, ticket) do
    if Authz.can_view_ticket?(scope, ticket), do: :ok, else: {:error, :unauthorized}
  end

  # Updates, logs and broadcasts; returns the ticket with its clear-text fields kept.
  def update_and_log(changeset, %Scope{user: user}, action, meta) do
    with {:ok, updated} <- Repo.update(changeset) do
      Bbh.Tickets.log_event(updated, user, action, meta)
      broadcast(updated)
      ServerCopies.release_on_change(changeset.data, updated)
      {:ok, updated}
    end
  end

  def tap_ok({:ok, value} = result, fun) do
    fun.(value)
    result
  end

  def tap_ok(other, _fun), do: other
end
