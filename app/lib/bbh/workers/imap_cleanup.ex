defmodule Bbh.Workers.ImapCleanup do
  @moduledoc """
  Removes a ticket's mail from the server once work on it started (plan §6.2): the
  database holds it now, encrypted; the copy in `Tickets/Importiert` only duplicates it
  in clear text. `"delete"` expunges it. `"junk"` moves it to `Junk` (marked as spam,
  so rspamd learns) and remembers it there; `"unjunk"` (spam marking taken back) moves
  it from `Junk` to `INBOX`, so rspamd learns the opposite and the poller files it
  again like any new mail.

  Retried on an IMAP error. Never touches a message the ticket does not reference by
  mailbox + UIDVALIDITY + UID: with a changed UIDVALIDITY the UID means another mail.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [period: 300, keys: [:ticket_id, :action]]

  require Logger

  alias Bbh.Imap
  alias Bbh.Repo
  alias Bbh.Tickets
  alias Bbh.Tickets.{Mailbox, Ticket}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"ticket_id" => ticket_id, "action" => action}}) do
    case Repo.get(Ticket, ticket_id) do
      %Ticket{} = ticket -> clean_ticket(ticket, action)
      nil -> :ok
    end
  end

  @doc """
  Removes all server copies of a ticket now (`"delete"` or `"junk"`). `:ok` when none
  are left, `{:error, :imap_disabled}` when copies exist but there is no mailbox
  configured to remove them from, `{:error, reason}` on an IMAP error.
  """
  def clean_ticket(%Ticket{} = ticket, action) do
    with [_ | _] = messages <- Tickets.server_copies(ticket),
         {:ok, conn} <- Mailbox.connect() do
      try do
        messages
        |> Enum.group_by(& &1.imap_mailbox)
        |> Enum.each(fn {mailbox, messages} -> clean(conn, mailbox, messages, action) end)
      after
        Imap.logout(conn)
      end

      :ok
    else
      [] -> :ok
      :disabled -> {:error, :imap_disabled}
      {:error, reason} -> {:error, reason}
    end
  end

  defp clean(conn, mailbox, messages, action) do
    {:ok, %{uidvalidity: validity}} = Imap.select(conn, mailbox)

    for message <- messages do
      if message.imap_uidvalidity == validity do
        apply_action(conn, mailbox, message, action)
      else
        # The UID belongs to another mail now; leave it, forget ours.
        Logger.warning("Postfach cleanup: UIDVALIDITY of #{mailbox} changed, copy left alone")
        Tickets.server_copy_removed(message, "uidvalidity_changed")
      end
    end
  end

  defp apply_action(conn, mailbox, message, "junk") do
    if mailbox != Mailbox.junk(), do: move(conn, message, Mailbox.junk(), "junk")
  end

  defp apply_action(conn, mailbox, message, "unjunk") do
    if mailbox == Mailbox.junk(), do: move(conn, message, Mailbox.inbox(), "unjunk")
  end

  defp apply_action(conn, _mailbox, message, _delete) do
    :ok = Imap.uid_delete(conn, message.imap_uid)
    Tickets.server_copy_removed(message, "delete")
  end

  defp move(conn, message, folder, action) do
    case Imap.uid_move(conn, message.imap_uid, folder) do
      {:ok, %{uidvalidity: validity, uid: uid}} ->
        Tickets.server_copy_moved(message, folder, validity, uid, action)

      {:ok, nil} ->
        # Moved, but the server did not say where: we can no longer find it.
        Tickets.server_copy_removed(message, action)
    end
  end
end
