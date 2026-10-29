defmodule Bbh.Tickets.Threading do
  @moduledoc """
  Finds the ticket an inbound mail belongs to (plan §7.2), in this order:

    1. `In-Reply-To` / `References` name one of our outbound Message-IDs.
    2. The subject carries a `[#BB-YYYY-NNNN]` token of an existing ticket — and the
       sender is the ticket's requester (blind index), or the ticket was never answered.
       Guessing a number must not let a stranger write into someone else's ticket.
    3. Otherwise: a new ticket.

  Deleted tickets are not found; a reply to one starts a new ticket.
  """
  import Ecto.Query

  alias Bbh.Repo
  alias Bbh.Tickets.{Message, Ticket}
  alias Bbh.Vault

  @doc """
  `%{message_ids: [raw ids from In-Reply-To and References], subject:, from:}` →
  `{:ok, ticket}` or `:none`.
  """
  def match(%{} = mail) do
    with :none <- by_message_id(mail[:message_ids] || []),
         :none <- by_token(mail[:subject], mail[:from]) do
      :none
    end
  end

  defp by_message_id([]), do: :none

  defp by_message_id(ids) do
    query =
      from t in Ticket,
        join: m in Message,
        on: m.ticket_id == t.id,
        where: m.direction == "out" and m.message_id in ^ids and is_nil(t.deleted_at),
        limit: 1

    found(Repo.one(query))
  end

  defp by_token(subject, from) when is_binary(subject) do
    with [_, number] <- Regex.run(~r/\[#BB-\d{4}-(\d+)\]/i, subject),
         %Ticket{deleted_at: nil} = ticket <-
           Repo.get_by(Ticket, number: String.to_integer(number)),
         true <- same_requester?(ticket, from) or never_answered?(ticket) do
      {:ok, ticket}
    else
      _ -> :none
    end
  end

  defp by_token(_subject, _from), do: :none

  defp same_requester?(%Ticket{requester_email_hmac: hmac}, from) when is_binary(from),
    do: hmac != nil and hmac == Vault.blind_index(from)

  defp same_requester?(_ticket, _from), do: false

  defp never_answered?(%Ticket{id: id}),
    do: not Repo.exists?(from m in Message, where: m.ticket_id == ^id and m.direction == "out")

  defp found(nil), do: :none
  defp found(ticket), do: {:ok, ticket}
end
