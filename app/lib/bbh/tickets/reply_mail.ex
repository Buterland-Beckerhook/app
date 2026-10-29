defmodule Bbh.Tickets.ReplyMail do
  @moduledoc """
  The mail a reply from the Postfach becomes: sent as the queue's address (membership
  replies as the Vorstand's), plain text, with our own Message-ID and the headers that
  thread it in the requester's mail client — and back into the ticket when they answer
  (`Bbh.Tickets.Threading`).
  """
  import Swoosh.Email

  alias Bbh.Tickets.{Queue, Ticket}

  @club "Schützenverein Buterland-Beckerhook"

  @doc """
  Builds the email for an outbound `message` of `ticket` (both decrypted). `inbound`
  is the latest inbound message, or nil: its Message-ID threads the reply, and a contact
  request is quoted below the answer so the requester sees what it answers.
  """
  def build(%Ticket{} = ticket, message, inbound) do
    sender = {"#{@club} – #{Queue.label(ticket.queue)}", Queue.reply_address(ticket.queue)}

    new()
    |> from(sender)
    |> reply_to(sender)
    |> to({ticket.requester_name || "", message.to})
    |> subject(subject(ticket))
    |> text_body(body(ticket, message, inbound))
    |> header("Message-ID", message.message_id)
    |> header("Auto-Submitted", "no")
    |> thread_headers(inbound)
  end

  @doc ~s(The subject: "Re: …" for mail, a fixed one for forms — always with the reference.)
  def subject(%Ticket{kind: "email", subject: subject} = ticket) do
    token = token(ticket)
    subject = String.trim(subject || "")

    cond do
      String.contains?(subject, token) -> subject
      String.match?(subject, ~r/^(re|aw):/i) -> "#{subject} #{token}"
      true -> "Re: #{subject} #{token}"
    end
  end

  def subject(%Ticket{kind: "membership"} = ticket), do: "Ihr Aufnahmeantrag #{token(ticket)}"
  def subject(ticket), do: "Ihre Anfrage #{token(ticket)}"

  @doc ~s(The token in the subject that threads an answer back, e.g. "[#BB-2026-0042]".)
  def token(ticket), do: "[##{Ticket.reference(ticket)}]"

  defp body(ticket, message, inbound) do
    """
    #{String.trim_trailing(message.body)}

    --
    #{@club} e.V.
    #{Queue.label(ticket.queue)}
    https://buterland-beckerhook.de
    #{quote_inbound(ticket, inbound)}\
    """
  end

  # Never quote a membership application: it is the form's summary, IBAN and all.
  defp quote_inbound(%Ticket{kind: "membership"}, _inbound), do: ""
  defp quote_inbound(_ticket, nil), do: ""

  defp quote_inbound(_ticket, inbound) do
    date =
      inbound.inserted_at
      |> DateTime.shift_zone!(Bbh.Time.time_zone())
      |> Calendar.strftime("%d.%m.%Y um %H:%M")

    quoted =
      (inbound.body || "")
      |> String.split("\n")
      |> Enum.map_join("\n", &("> " <> &1))

    "\nAm #{date} schrieben Sie:\n#{quoted}\n"
  end

  defp thread_headers(email, %{header_message_id: id}) when is_binary(id) and id != "" do
    email |> header("In-Reply-To", id) |> header("References", id)
  end

  defp thread_headers(email, _inbound), do: email
end
