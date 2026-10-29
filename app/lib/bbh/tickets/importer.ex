defmodule Bbh.Tickets.Importer do
  @moduledoc """
  Turns one raw mail from the Postfach mailbox into a ticket, a reply on a ticket, or
  nothing (plan §6.2). Called by `Bbh.Workers.ImapPoller` per message; idempotent by the
  hashed Message-ID, so a mail imported but not yet moved is just moved next time.

  In order:

    1. Already imported → `:duplicate`.
    2. Loops: a mail delivered to the collector mailbox more than once → `:ignored`.
    3. Bounces (from the mailer daemon, or a delivery report) that name one of our
       replies → a system note "nicht zugestellt" on that ticket (`{:bounce, ticket}`);
       other bounces, auto-replies (`Auto-Submitted`), bulk/list mail and mail from our
       own addresses → `:ignored`. Never an automatic answer: no backscatter.
    4. A reply to an existing ticket (`Bbh.Tickets.Threading`) → `{:appended, ticket}`.
    5. Otherwise a new ticket in the queue of the top-most `X-Original-To` (`info` if
       none matches), `spam` above `TICKET_SPAM_SCORE` → `{:created, ticket}`.

  Attachments above `TICKET_MAX_ATTACHMENT_MB` are dropped with a system note.
  """

  import Ecto.Query

  alias Bbh.Repo
  alias Bbh.Tickets
  alias Bbh.Tickets.{InboundMail, Message, Queue, Threading, Ticket}

  @doc """
  Imports `raw`. `location`: `%{imap_mailbox:, imap_uidvalidity:, imap_uid:}` of the
  mail on the server, stored with the message (optional).
  """
  def import(raw, location \\ %{}) do
    case InboundMail.parse(raw) do
      {:ok, mail} -> import_mail(mail, raw, location)
      {:error, :unparseable} -> :ignored
    end
  end

  defp import_mail(mail, raw, location) do
    cond do
      duplicate?(mail) -> :duplicate
      loop?(mail) -> :ignored
      bounce?(mail) -> bounce(raw)
      automatic?(mail) -> :ignored
      true -> file(mail, location)
    end
  end

  defp duplicate?(%InboundMail{message_id_hash: hash}) do
    Repo.exists?(from m in Message, where: m.direction == "in" and m.message_id == ^hash)
  end

  # Delivered to the collector mailbox before: a forwarding loop.
  defp loop?(%InboundMail{delivered_to: delivered}) do
    collector = collector_address()
    collector != nil and Enum.count(delivered, &(&1 == collector)) > 1
  end

  defp bounce?(%InboundMail{from_email: from, report?: report?}) do
    report? or from in [nil, ""] or String.starts_with?(from, ["mailer-daemon@", "postmaster@"])
  end

  defp automatic?(%InboundMail{} = mail) do
    mail.auto_submitted not in [nil, "no"] or
      mail.precedence in ["bulk", "list", "junk"] or
      mail.from_email in own_addresses()
  end

  # A bounce of one of our replies names its Message-ID somewhere in the report.
  defp bounce(raw) do
    ids =
      Regex.scan(~r/<[0-9a-f-]{36}@buterland-beckerhook\.de>/i, raw)
      |> List.flatten()
      |> Enum.map(&String.downcase/1)
      |> Enum.uniq()

    query =
      from t in Ticket,
        join: m in Message,
        on: m.ticket_id == t.id,
        where: m.direction == "out" and m.message_id in ^ids and is_nil(t.deleted_at),
        limit: 1

    case ids != [] && Repo.one(query) do
      %Ticket{} = ticket ->
        Tickets.add_system_note(
          ticket,
          "Eine Antwort konnte nicht zugestellt werden (Rückmeldung des Mailservers). " <>
            "Bitte die Adresse prüfen."
        )

        {:bounce, ticket}

      _ ->
        :ignored
    end
  end

  defp file(mail, location) do
    {attachments, dropped} = split_attachments(mail.attachments)

    message =
      Map.merge(location, %{
        body: mail.text,
        from: mail.from_email,
        to: mail.original_to,
        message_id: mail.message_id_hash,
        header_message_id: mail.message_id,
        in_reply_to: mail.reply_ids |> List.first() |> hash()
      })

    case Threading.match(%{
           message_ids: mail.reply_ids,
           subject: mail.subject,
           from: mail.from_email
         }) do
      {:ok, ticket} ->
        with {:ok, {updated, _message}} <-
               Tickets.add_inbound(ticket, message, attachments: attachments, notes: dropped) do
          {:appended, updated}
        end

      :none ->
        queue = Queue.for_address(mail.original_to) || Queue.default()
        spam? = is_float(mail.spam_score) and mail.spam_score >= spam_threshold()

        attrs = %{
          queue: queue,
          kind: "email",
          status: if(spam?, do: "spam", else: "new"),
          subject: mail.subject,
          requester_name: mail.from_name,
          requester_email: mail.from_email,
          spam_score: mail.spam_score
        }

        notes = dropped ++ also_addressed(mail, queue)

        with {:ok, ticket} <-
               Tickets.create_ticket(attrs, message, attachments: attachments, notes: notes) do
          {:created, ticket}
        end
    end
  end

  defp split_attachments(attachments) do
    limit = max_attachment_bytes()
    {keep, drop} = Enum.split_with(attachments, &(&1.size <= limit))

    notes =
      for a <- drop do
        "Anhang „#{a.filename}“ (#{Float.round(a.size / 1_048_576, 1)} MB) war zu groß " <>
          "und wurde nicht übernommen."
      end

    {keep, notes}
  end

  # One mail to several queue addresses becomes one ticket; the others are noted.
  defp also_addressed(mail, queue) do
    others =
      (mail.to ++ mail.cc)
      |> Enum.map(&Queue.for_address/1)
      |> Enum.reject(&(&1 in [nil, queue]))
      |> Enum.uniq()

    case others do
      [] -> []
      keys -> ["Auch adressiert an: " <> Enum.map_join(keys, ", ", &Queue.label/1)]
    end
  end

  defp hash(nil), do: nil
  defp hash(value), do: InboundMail.sha256(value)

  ## Configuration

  defp own_addresses do
    queue_addresses =
      for key <- Queue.keys(), a = Queue.inbound_address(key), a, do: String.downcase(a)

    [collector_address(), String.downcase(Bbh.Mailer.sender()) | queue_addresses]
    |> Enum.reject(&is_nil/1)
  end

  defp collector_address do
    case Application.get_env(:bbh, :ticket_imap, [])[:username] do
      nil -> nil
      username -> String.downcase(username)
    end
  end

  @doc "Spam score from which an inbound mail is filed as spam (`TICKET_SPAM_SCORE`)."
  def spam_threshold, do: Application.get_env(:bbh, :ticket_spam_score, 6.0)

  defp max_attachment_bytes,
    do: Application.get_env(:bbh, :ticket_max_attachment_mb, 10) * 1_048_576
end
