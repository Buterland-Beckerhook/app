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

  describe "Junk" do
    @spam "X-Original-To: info@buterland-beckerhook.de\r\nFrom: Win <win@spam.example>\r\n" <>
            "Subject: Gewinn\r\nMessage-ID: <junk1@spam.example>\r\nContent-Type: text/plain\r\n\r\nKlick\r\n"

    test "with TICKET_IMPORT_JUNK the poller files new Junk mail as spam and remembers where it stopped" do
      Application.put_env(:bbh, :ticket_import_junk, true)
      on_exit(fn -> Application.delete_env(:bbh, :ticket_import_junk) end)
      Bbh.Settings.put_ticket_junk_position(77, 4)
      size = byte_size(@spam)

      {port, _} =
        FakeImap.start(
          FakeImap.login_steps() ++
            [
              {~r/^CREATE "Tickets\/Importiert"$/, ["TAG OK"]},
              {~r/^CREATE "Tickets\/Ignoriert"$/, ["TAG OK"]},
              {~r/^SELECT "INBOX"$/, ["* OK [UIDVALIDITY 11] ok", "TAG OK"]},
              {~r/^UID SEARCH ALL$/, ["* SEARCH", "TAG OK"]},
              {~r/^SELECT "Junk"$/, ["* OK [UIDVALIDITY 77] ok", "TAG OK"]},
              # "5:*" also names the last message (4) — it must be skipped.
              {~r/^UID SEARCH UID 5:\*$/, ["* SEARCH 4 6", "TAG OK"]},
              {~r/^UID FETCH 6 \(RFC822.SIZE\)$/,
               ["* 1 FETCH (UID 6 RFC822.SIZE #{size})", "TAG OK"]},
              {~r/^UID FETCH 6 \(BODY.PEEK\[\]\)$/,
               ["* 1 FETCH (UID 6 BODY[] {#{size}}", @spam <> ")", "TAG OK"]},
              {~r/^LOGOUT$/, ["* BYE", "TAG OK"]}
            ]
        )

      configure(port)
      assert :ok = perform_job(ImapPoller, %{})
      assert_receive {:fake_imap_done, :ok}

      [ticket] = Repo.all(Ticket)
      assert ticket.status == "spam"
      assert %{imap_mailbox: "Junk", imap_uid: 6} = Repo.get_by!(Message, direction: "in")
      assert Bbh.Settings.ticket_junk_position() == {77, 6}
    end

    test "without it, Junk is never read (the default)" do
      {port, _} =
        FakeImap.start(
          FakeImap.login_steps() ++
            [
              {~r/^CREATE/, ["TAG OK"]},
              {~r/^CREATE/, ["TAG OK"]},
              {~r/^SELECT "INBOX"$/, ["* OK [UIDVALIDITY 11] ok", "TAG OK"]},
              {~r/^UID SEARCH ALL$/, ["* SEARCH", "TAG OK"]},
              {~r/^LOGOUT$/, ["* BYE", "TAG OK"]}
            ]
        )

      configure(port)
      assert :ok = perform_job(ImapPoller, %{})
      assert_receive {:fake_imap_done, :ok}
    end

    test "spam goes to Junk and is remembered there; Kein Spam moves it back to INBOX" do
      {:created, ticket} =
        Tickets.Importer.import(@mail, %{
          imap_mailbox: "Tickets/Importiert",
          imap_uidvalidity: 22,
          imap_uid: 99
        })

      scope = Bbh.TicketsFixtures.granted_scope(user_fixture(), ["info"])
      {:ok, spam} = Tickets.mark_spam(scope, ticket)

      {port, _} =
        FakeImap.start(
          FakeImap.login_steps() ++
            [
              {~r/^SELECT "Tickets\/Importiert"$/, ["* OK [UIDVALIDITY 22] ok", "TAG OK"]},
              {~r/^UID MOVE 99 "Junk"$/, ["* OK [COPYUID 77 99 12] Moved", "TAG OK"]},
              {~r/^LOGOUT$/, ["* BYE", "TAG OK"]}
            ]
        )

      configure(port)
      assert :ok = perform_job(ImapCleanup, %{ticket_id: ticket.id, action: "junk"})
      assert_receive {:fake_imap_done, :ok}

      assert %{imap_mailbox: "Junk", imap_uid: 12, server_copy_removed_at: nil} =
               Repo.get_by!(Message, direction: "in")

      {:ok, _} = Tickets.unmark_spam(scope, spam)
      assert_enqueued(worker: ImapCleanup, args: %{ticket_id: ticket.id, action: "unjunk"})

      {port, _} =
        FakeImap.start(
          FakeImap.login_steps() ++
            [
              {~r/^SELECT "Junk"$/, ["* OK [UIDVALIDITY 77] ok", "TAG OK"]},
              {~r/^UID MOVE 12 "INBOX"$/, ["* OK [COPYUID 11 12 50] Moved", "TAG OK"]},
              {~r/^LOGOUT$/, ["* BYE", "TAG OK"]}
            ]
        )

      configure(port)
      assert :ok = perform_job(ImapCleanup, %{ticket_id: ticket.id, action: "unjunk"})
      assert_receive {:fake_imap_done, :ok}
      assert %{imap_mailbox: "INBOX", imap_uid: 50} = Repo.get_by!(Message, direction: "in")
    end
  end
end
