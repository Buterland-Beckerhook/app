defmodule Bbh.Tickets.Replies do
  @moduledoc """
  Answering the requester by mail from the Postfach: storing the reply and moving the
  ticket on (`reply/4`), sending it in a job (`deliver_reply/1`, called by
  `Bbh.Workers.TicketReplySender`) and noting a reply that could not be sent.
  """
  import Ecto.Query
  import Bbh.Tickets.Store, only: [authorize: 2, broadcast: 1, insert_message: 2, tap_ok: 2]

  alias Bbh.Accounts.Scope
  alias Bbh.Repo
  alias Bbh.Tickets
  alias Bbh.Tickets.{Message, Queue, ServerCopies, Ticket}
  alias Bbh.Vault

  @doc "Whether replies can be sent from the Postfach (`Bbh.Tickets.Mailer` configured)."
  def replies_enabled?, do: Bbh.Tickets.Mailer.enabled?()

  @doc """
  Answers the requester from the queue's address (`Bbh.Tickets.ReplyMail`). The reply
  is stored, the ticket set to `status` (`waiting` by default, or `open`/`closed`) and
  taken by the replier if nobody had it; the mail itself goes out in a job
  (`Bbh.Workers.TicketReplySender`).
  """
  def reply(%Scope{user: user} = scope, %Ticket{} = ticket, body, status \\ "waiting") do
    body = String.trim(body || "")

    with :ok <- authorize(scope, ticket),
         true <- replies_enabled?() || {:error, :replies_disabled},
         true <- ticket.requester_email not in [nil, ""] || {:error, :no_recipient},
         true <- ticket.status != "spam" || {:error, :spam},
         true <- body != "" || {:error, :empty},
         true <- status in ~w(open waiting closed) || {:error, :invalid_status} do
      Repo.transact(fn ->
        message_attrs = %{
          direction: "out",
          author_id: user.id,
          from: Queue.reply_address(ticket.queue),
          to: ticket.requester_email,
          body: body,
          message_id: "<#{Ecto.UUID.generate()}@buterland-beckerhook.de>"
        }

        with {:ok, message} <- insert_message(ticket, message_attrs),
             {:ok, updated} <-
               ticket
               |> Ticket.status_changeset(status, nil)
               |> Ecto.Changeset.put_change(:assignee_id, ticket.assignee_id || user.id)
               |> Repo.update() do
          Tickets.log_event(updated, user, "replied", %{status: status})
          ServerCopies.release_on_change(ticket, updated)
          %{message_id: message.id} |> Bbh.Workers.TicketReplySender.new() |> Oban.insert!()
          {:ok, updated}
        end
      end)
      |> tap_ok(&broadcast/1)
    end
  end

  @doc false
  # Sends a stored reply (called by Bbh.Workers.TicketReplySender). `:ok` also when it
  # already went out or is gone; `{:error, :delivery_failed}` to retry — the reason
  # itself is logged by the mailer, not stored in the job (it may name the address).
  def deliver_reply(message_id) do
    with %Message{direction: "out", sent_at: nil} = message <- Repo.get(Message, message_id),
         %Ticket{} = ticket <- Repo.get(Ticket, message.ticket_id) do
      message = Vault.decrypt_fields(message, "ticket_messages", Message.encrypted_fields())
      ticket = Vault.decrypt_fields(ticket, "tickets", Ticket.encrypted_fields())
      email = Bbh.Tickets.ReplyMail.build(ticket, message, latest_inbound(ticket))

      case Bbh.Mailer.deliver_logged(email, "ticket-reply",
             redact: true,
             mailer: Bbh.Tickets.Mailer
           ) do
        {:ok, _} ->
          message |> Ecto.Changeset.change(sent_at: DateTime.utc_now(:second)) |> Repo.update!()
          broadcast(ticket)
          :ok

        {:error, _reason} ->
          {:error, :delivery_failed}
      end
    else
      _ -> :ok
    end
  end

  @doc false
  # The last attempt failed: say so on the ticket.
  def reply_failed(message_id) do
    with %Message{} = message <- Repo.get(Message, message_id),
         %Ticket{} = ticket <- Repo.get(Ticket, message.ticket_id) do
      date =
        message.inserted_at
        |> DateTime.shift_zone!(Bbh.Time.time_zone())
        |> Calendar.strftime("%d.%m.%Y, %H:%M Uhr")

      {:ok, _} =
        insert_message(ticket, %{
          direction: "system",
          body:
            "Die Antwort vom #{date} konnte nicht gesendet werden. Bitte die Adresse " <>
              "prüfen und erneut antworten."
        })

      broadcast(ticket)
    end

    :ok
  end

  defp latest_inbound(%Ticket{id: id}) do
    from(m in Message,
      where: m.ticket_id == ^id and m.direction == "in",
      order_by: [desc: m.inserted_at],
      limit: 1
    )
    |> Repo.one()
    |> case do
      nil -> nil
      message -> Vault.decrypt_fields(message, "ticket_messages", Message.encrypted_fields())
    end
  end
end
