defmodule Bbh.Tickets.Notifier do
  @moduledoc """
  Postfach mails to staff: new requests, assignments, reminders and the admin digest.

  They carry **no personal data** — no subject, no name, no sender address — only the
  queue, the ticket reference and a link into the Postfach, which needs a login with a
  passkey or second factor. A mail account that is read on a phone or forwarded must not
  leak what the request is about. Sent from the system address (`noreply@`), like the
  login mails.
  """
  import Swoosh.Email

  alias Bbh.Mailer
  alias Bbh.Tickets.{Queue, Ticket}

  @doc "New requests in the user's queues, bundled into one mail."
  def new_tickets(user, [ticket]) do
    deliver(user, "Postfach: neue Anfrage (#{Queue.label(ticket.queue)})", """
    Hallo,

    im Postfach „#{Queue.label(ticket.queue)}“ ist eine neue Anfrage eingegangen: #{Ticket.reference(ticket)}.

    Bearbeiten: #{url(ticket)}
    #{footer()}
    """)
  end

  def new_tickets(user, tickets) do
    deliver(user, "Postfach: #{length(tickets)} neue Anfragen", """
    Hallo,

    in deinen Postfächern sind neue Anfragen eingegangen:

    #{lines(tickets)}
    #{footer()}
    """)
  end

  @doc "The requester answered on a ticket the user has (or whose queue they work)."
  def reply_received(user, ticket) do
    deliver(user, "Postfach: neue Antwort zu #{Ticket.reference(ticket)}", """
    Hallo,

    zur Anfrage #{Ticket.reference(ticket)} im Postfach „#{Queue.label(ticket.queue)}“ ist eine Antwort eingegangen.

    Bearbeiten: #{url(ticket)}
    #{footer()}
    """)
  end

  @doc "Someone else assigned the user a ticket."
  def assigned(user, ticket, by) do
    deliver(user, "Postfach: #{Ticket.reference(ticket)} wurde dir zugewiesen", """
    Hallo,

    #{by.email} hat dir im Postfach „#{Queue.label(ticket.queue)}“ die Anfrage #{Ticket.reference(ticket)} zugewiesen.

    Bearbeiten: #{url(ticket)}
    #{footer()}
    """)
  end

  @doc "The daily reminder: `items` is `[{ticket, reason}]`."
  def reminders(user, items) do
    subject =
      case items do
        [_] -> "Postfach: eine Anfrage wartet"
        _ -> "Postfach: #{length(items)} Anfragen warten"
      end

    deliver(user, subject, """
    Hallo,

    diese Anfragen brauchen deine Aufmerksamkeit:

    #{lines(items)}
    #{footer()}
    """)
  end

  @doc """
  The admin digest: `counts` is `%{queue => %{status => n}}` of the tickets in work,
  `overdue` and `escalations` lists of tickets.
  """
  def digest(admin, %{counts: counts, overdue: overdue, escalations: escalations}) do
    deliver(admin, "Postfach: Tagesübersicht", """
    Hallo,

    die Lage im Postfach:

    #{count_lines(counts)}
    #{section("Seit Tagen niemandem zugewiesen", escalations)}#{section("Überfällig", overdue)}
    Postfach: #{BbhWeb.Endpoint.url()}/admin/postfach
    #{footer()}
    """)
  end

  defp section(_title, []), do: ""
  defp section(title, tickets), do: "#{title}:\n\n#{lines(tickets)}\n"

  defp count_lines(counts) when counts == %{}, do: "Keine offenen Anfragen.\n"

  defp count_lines(counts) do
    for key <- Queue.keys(), statuses = counts[key], statuses do
      parts =
        for status <- Ticket.active_statuses(),
            n = statuses[status],
            n,
            do: "#{n} #{Ticket.status_label(status)}"

      "#{Queue.label(key)}: #{Enum.join(parts, ", ")}"
    end
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  # Tickets, or `{ticket, reason}` pairs.
  defp lines(entries) do
    Enum.map_join(entries, "\n", fn
      {ticket, reason} -> line(ticket, " – #{reason}")
      ticket -> line(ticket, "")
    end)
  end

  defp line(ticket, suffix),
    do: "#{Ticket.reference(ticket)} · #{Queue.label(ticket.queue)}#{suffix}\n  #{url(ticket)}"

  defp url(ticket), do: "#{BbhWeb.Endpoint.url()}/admin/postfach/#{Ticket.reference(ticket)}"

  defp footer do
    """

    --
    Diese Nachricht enthält bewusst keine Inhalte der Anfrage. Die Benachrichtigungen
    richten sich nach deinen Postfach-Freigaben in der Benutzerverwaltung.
    """
  end

  defp deliver(user, subject, body) do
    new()
    |> to(user.email)
    |> from({Mailer.sender_name(), Mailer.sender()})
    |> subject(subject)
    |> text_body(body)
    |> Mailer.deliver_logged("tickets")
  end
end
