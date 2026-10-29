defmodule Bbh.Workers.ImapPoller do
  @moduledoc """
  Fetches new mail from the Postfach mailbox every two minutes and files it
  (`Bbh.Tickets.Importer`), then moves it out of `INBOX`:

    * a new ticket or a reply → `Tickets/Importiert` (deleted there once work starts,
      see `Bbh.Workers.ImapCleanup`)
    * spam → `Junk`
    * ignored, bounced, oversized → `Tickets/Ignoriert`

  Reads only `INBOX`; mailcow's rspamd has already moved high-score mail to `Junk`.
  `BODY.PEEK[]` leaves the read flag alone. Idempotent: a mail imported but not moved
  (connection lost in between) is found as a duplicate next time and just moved.
  Logs carry UIDs and outcomes only, never addresses or subjects.
  """
  use Oban.Worker, queue: :default, max_attempts: 1, unique: [period: 110]

  require Logger

  alias Bbh.Imap
  alias Bbh.Tickets
  alias Bbh.Tickets.{Importer, InboundMail, Mailbox}

  @batch 50

  @impl Oban.Worker
  def perform(_job) do
    case Mailbox.connect() do
      :disabled ->
        :ok

      {:ok, conn} ->
        try do
          poll(conn)
        after
          Imap.logout(conn)
        end

      {:error, reason} ->
        Logger.warning("Postfach import: IMAP connection failed: #{inspect(reason)}")
        :ok
    end
  end

  defp poll(conn) do
    for folder <- [Mailbox.imported(), Mailbox.ignored()], do: :ok = Imap.create(conn, folder)
    {:ok, %{uidvalidity: uidvalidity}} = Imap.select(conn, Mailbox.inbox())
    {:ok, uids} = Imap.uid_search(conn)

    uids
    |> Enum.take(@batch)
    |> Enum.each(&process(conn, &1, uidvalidity))

    :ok
  end

  defp process(conn, uid, uidvalidity) do
    with {:ok, size} when is_integer(size) <- Imap.uid_size(conn, uid) do
      if size > Mailbox.max_mail_bytes() do
        Logger.warning("Postfach import: UID #{uid} too large (#{size} bytes), set aside")
        Imap.uid_move(conn, uid, Mailbox.ignored())
      else
        import(conn, uid, uidvalidity)
      end
    end
  end

  defp import(conn, uid, uidvalidity) do
    with {:ok, raw} when is_binary(raw) <- Imap.uid_fetch(conn, uid) do
      location = %{imap_mailbox: Mailbox.inbox(), imap_uidvalidity: uidvalidity, imap_uid: uid}
      result = Importer.import(raw, location)
      Logger.info("Postfach import: UID #{uid} → #{outcome(result)}")

      case result do
        {:created, %{status: "spam"}} ->
          file(conn, uid, raw, Mailbox.junk())

        {kind, _ticket} when kind in [:created, :appended] ->
          file(conn, uid, raw, Mailbox.imported())

        :duplicate ->
          file(conn, uid, raw, Mailbox.imported())

        _ignored_or_bounce ->
          Imap.uid_move(conn, uid, Mailbox.ignored())
      end
    end
  end

  # Move it and remember where it went (the INBOX UID is stale after the move); a ticket
  # already in work drops the copy at once.
  defp file(conn, uid, raw, folder) do
    with {:ok, %{uidvalidity: validity, uid: new_uid}} <- Imap.uid_move(conn, uid, folder) do
      hash =
        case InboundMail.parse(raw) do
          {:ok, mail} -> mail.message_id_hash
          _ -> InboundMail.sha256(raw)
        end

      with %{} = ticket <- Tickets.record_server_copy(hash, folder, validity, new_uid) do
        Tickets.release_new_server_copy(ticket)
      end
    end
  end

  defp outcome({kind, _}), do: kind
  defp outcome(kind), do: kind
end
