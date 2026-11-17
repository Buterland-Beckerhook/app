defmodule Bbh.Tickets.Requesters do
  @moduledoc """
  Requests for access and erasure (Art. 15 / 17 GDPR): every ticket of an e-mail
  address, and deleting them. Admins only. Used by `BbhWeb.Admin.TicketLive.Requester`.
  """
  import Ecto.Query
  import Bbh.Tickets.Store, only: [broadcast: 1]

  alias Bbh.Accounts.Scope
  alias Bbh.Authz
  alias Bbh.Repo
  alias Bbh.Tickets
  alias Bbh.Tickets.{ServerCopies, Ticket}
  alias Bbh.Vault

  @doc """
  Every ticket of an e-mail address — all queues, deleted ones too, until purged —
  found by its blind index. Admins only; the lookup is logged without the address.
  """
  def requester_tickets(%Scope{user: user} = scope, email) do
    if Authz.can_delete_ticket?(scope) do
      tickets =
        Repo.all(
          from t in Ticket,
            where: t.requester_email_hmac == ^Vault.blind_index(email),
            order_by: [desc: t.inserted_at]
        )
        |> Enum.map(&Vault.decrypt_fields(&1, "tickets", Ticket.encrypted_fields()))

      Tickets.log_event(nil, user, "requester_lookup", %{count: length(tickets)})
      {:ok, tickets}
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Deletes every ticket of an e-mail address: soft (`purge: false`, restorable for
  `TICKET_PURGE_DAYS`) or for good right away (`purge: true`, server copies first).
  Returns how many.
  """
  def delete_requester_tickets(%Scope{user: user} = scope, email, opts \\ []) do
    with {:ok, tickets} <- requester_tickets(scope, email) do
      count =
        if opts[:purge] do
          Enum.count(tickets, &Bbh.Tickets.Retention.purge_ticket/1)
        else
          tickets
          |> Enum.filter(&is_nil(&1.deleted_at))
          |> Enum.count(fn ticket ->
            ticket
            |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second))
            |> Repo.update!()
            |> tap(&Tickets.log_event(&1, user, "deleted", %{reason: "requester"}))
            |> tap(&ServerCopies.release_deleted/1)
            |> tap(&broadcast/1)
          end)
        end

      {:ok, count}
    end
  end
end
