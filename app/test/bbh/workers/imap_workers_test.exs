defmodule Bbh.Workers.ImapWorkersTest do
  use Bbh.DataCase, async: false
  use Oban.Testing, repo: Bbh.Repo

  import Bbh.AccountsFixtures

  alias Bbh.FakeImap
  alias Bbh.Tickets
  alias Bbh.Tickets.{Message, Ticket}
  alias Bbh.Workers.{ImapCleanup, ImapPoller}

  @mail "X-Original-To: info@buterland-beckerhook.de\r\nFrom: Max <max@example.com>\r\n" <>
          "Subject: Hallo\r\nMessage-ID: <poll@example.com>\r\nContent-Type: text/plain\r\n\r\nFrage\r\n"

  defp configure(port) do
    Application.put_env(:bbh, :ticket_imap,
      host: "127.0.0.1",
      port: port,
      tls: false,
      username: "tickets",
      password: "geheim"
    )

    on_exit(fn -> Application.delete_env(:bbh, :ticket_imap) end)
  end

  test "the poller imports new mail and files it in Tickets/Importiert" do
    size = byte_size(@mail)

    {port, _} =
      FakeImap.start(
        FakeImap.login_steps() ++
          [
            {~r/^CREATE "Tickets\/Importiert"$/, ["TAG OK Create completed"]},
            {~r/^CREATE "Tickets\/Ignoriert"$/, ["TAG NO [ALREADYEXISTS] exists"]},
            {~r/^SELECT "INBOX"$/, ["* 1 EXISTS", "* OK [UIDVALIDITY 11] ok", "TAG OK"]},
            {~r/^UID SEARCH ALL$/, ["* SEARCH 4", "TAG OK"]},
            {~r/^UID FETCH 4 \(RFC822.SIZE\)$/,
             ["* 1 FETCH (UID 4 RFC822.SIZE #{size})", "TAG OK"]},
            {~r/^UID FETCH 4 \(BODY.PEEK\[\]\)$/,
             ["* 1 FETCH (UID 4 BODY[] {#{size}}", @mail <> ")", "TAG OK"]},
            {~r/^UID MOVE 4 "Tickets\/Importiert"$/, ["* OK [COPYUID 22 4 99] Moved", "TAG OK"]},
            {~r/^LOGOUT$/, ["* BYE", "TAG OK"]}
          ]
      )

    configure(port)
    assert :ok = perform_job(ImapPoller, %{})
    assert_receive {:fake_imap_done, :ok}

    [ticket] = Repo.all(Ticket)
    assert %{queue: "info", kind: "email", status: "new"} = ticket

    message = Repo.get_by!(Message, direction: "in")
    assert %{imap_mailbox: "Tickets/Importiert", imap_uidvalidity: 22, imap_uid: 99} = message
  end

  test "the poller is a no-op without configuration" do
    Application.delete_env(:bbh, :ticket_imap)
    assert :ok = perform_job(ImapPoller, %{})
  end

  test "taking the ticket deletes its server copy" do
    {:created, ticket} =
      Tickets.Importer.import(@mail, %{
        imap_mailbox: "Tickets/Importiert",
        imap_uidvalidity: 22,
        imap_uid: 99
      })

    user = user_fixture()
    scope = Bbh.TicketsFixtures.granted_scope(user, ["info"])
    {:ok, _} = Tickets.take(scope, ticket)

    assert_enqueued(worker: ImapCleanup, args: %{ticket_id: ticket.id, action: "delete"})

    {port, _} =
      FakeImap.start(
        FakeImap.login_steps() ++
          [
            {~r/^SELECT "Tickets\/Importiert"$/, ["* OK [UIDVALIDITY 22] ok", "TAG OK"]},
            {~r/^UID STORE 99 \+FLAGS.SILENT \(\\Deleted\)$/, ["TAG OK"]},
            {~r/^UID EXPUNGE 99$/, ["TAG OK"]},
            {~r/^LOGOUT$/, ["* BYE", "TAG OK"]}
          ]
      )

    configure(port)
    assert :ok = perform_job(ImapCleanup, %{ticket_id: ticket.id, action: "delete"})
    assert_receive {:fake_imap_done, :ok}

    assert Repo.get_by!(Message, direction: "in").server_copy_removed_at
    assert "server_copy_removed" in Enum.map(Tickets.list_events(ticket), & &1.action)
  end

  test "marking as spam moves the copy to Junk; a changed UIDVALIDITY leaves it alone" do
    {:created, ticket} =
      Tickets.Importer.import(@mail, %{
        imap_mailbox: "Tickets/Importiert",
        imap_uidvalidity: 22,
        imap_uid: 99
      })

    scope = Bbh.TicketsFixtures.granted_scope(user_fixture(), ["info"])
    {:ok, _} = Tickets.mark_spam(scope, ticket)
    assert_enqueued(worker: ImapCleanup, args: %{ticket_id: ticket.id, action: "junk"})

    {port, _} =
      FakeImap.start(
        FakeImap.login_steps() ++
          [
            {~r/^SELECT "Tickets\/Importiert"$/, ["* OK [UIDVALIDITY 23] ok", "TAG OK"]},
            {~r/^LOGOUT$/, ["* BYE", "TAG OK"]}
          ]
      )

    configure(port)
    assert :ok = perform_job(ImapCleanup, %{ticket_id: ticket.id, action: "junk"})
    assert_receive {:fake_imap_done, :ok}
    assert Repo.get_by!(Message, direction: "in").server_copy_removed_at
  end

  test "form tickets have no server copy and queue no cleanup" do
    ticket = Bbh.TicketsFixtures.ticket_fixture()
    scope = Bbh.TicketsFixtures.granted_scope(user_fixture(), ["info"])
    {:ok, _} = Tickets.take(scope, ticket)
    refute_enqueued(worker: ImapCleanup)
  end
end
