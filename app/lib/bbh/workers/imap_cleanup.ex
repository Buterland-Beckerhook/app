defmodule Bbh.Workers.ImapCleanup do
  @moduledoc """
  Removes a ticket's mail from the server once work on it started (plan §6.2): the
  database holds it now, encrypted; the copy in `Tickets/Importiert` only duplicates it
  in clear text. `"delete"` expunges it, `"junk"` moves it to `Junk` (marked as spam, so
  rspamd learns).

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
        :ok = remove(conn, message.imap_uid, action)
        Tickets.server_copy_removed(message, action)
      else
        # The UID belongs to another mail now; leave it, forget ours.
        Logger.warning("Postfach cleanup: UIDVALIDITY of #{mailbox} changed, copy left alone")
        Tickets.server_copy_removed(message, "uidvalidity_changed")
      end
    end
  end

  defp remove(conn, uid, "junk") do
    with {:ok, _} <- Imap.uid_move(conn, uid, Mailbox.junk()), do: :ok
  end

  defp remove(conn, uid, _delete), do: Imap.uid_delete(conn, uid)
end
