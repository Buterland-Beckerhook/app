defmodule Bbh.Tickets.ImapTest do
  use ExUnit.Case, async: true

  alias Bbh.FakeImap
  alias Bbh.Tickets.Imap

  defp connect(port, opts \\ []) do
    Imap.connect(
      [
        host: "127.0.0.1",
        port: port,
        tls: false,
        username: "tickets",
        password: "geheim",
        timeout: 2_000
      ] ++
        opts
    )
  end

  test "logs in, selects, searches, fetches a literal, moves and deletes" do
    mail = "From: a@example.com\r\nSubject: Hallo\r\n\r\nÄrger mit {braces}\r\n"
    size = byte_size(mail)

    {port, _} =
      FakeImap.start(
        FakeImap.login_steps() ++
          [
            {~r/^CREATE "Tickets\/Importiert"$/,
             ["TAG NO [ALREADYEXISTS] Mailbox already exists"]},
            {~r/^SELECT "INBOX"$/,
             [
               "* 2 EXISTS",
               "* OK [UIDVALIDITY 1700000000] UIDs valid",
               "* OK [UIDNEXT 9] Predicted next UID",
               "TAG OK [READ-WRITE] Select completed"
             ]},
            {~r/^UID SEARCH ALL$/, ["* SEARCH 7 3", "TAG OK Search completed"]},
            {~r/^UID FETCH 3 \(RFC822.SIZE\)$/,
             ["* 1 FETCH (UID 3 RFC822.SIZE #{size})", "TAG OK"]},
            {~r/^UID FETCH 3 \(BODY.PEEK\[\]\)$/,
             ["* 1 FETCH (UID 3 BODY[] {#{size}}", mail <> ")", "TAG OK Fetch completed"]},
            {~r/^UID MOVE 3 "Tickets\/Importiert"$/,
             ["* OK [COPYUID 1700000001 3 41] Moved", "* 1 EXPUNGE", "TAG OK Move completed"]},
            {~r/^UID STORE 7 \+FLAGS.SILENT \(\\Deleted\)$/, ["TAG OK Store completed"]},
            {~r/^UID EXPUNGE 7$/, ["* 2 EXPUNGE", "TAG OK Expunge completed"]},
            {~r/^LOGOUT$/, ["* BYE Logging out", "TAG OK Logout completed"]}
          ]
      )

    assert {:ok, conn} = connect(port)
    assert "MOVE" in conn.capabilities
    assert :ok = Imap.create(conn, "Tickets/Importiert")

    assert {:ok, %{exists: 2, uidvalidity: 1_700_000_000, uidnext: 9}} =
             Imap.select(conn, "INBOX")

    assert {:ok, [3, 7]} = Imap.uid_search(conn)
    assert {:ok, ^size} = Imap.uid_size(conn, 3)
    assert {:ok, ^mail} = Imap.uid_fetch(conn, 3)

    assert {:ok, %{uidvalidity: 1_700_000_001, uid: 41}} =
             Imap.uid_move(conn, 3, "Tickets/Importiert")

    assert :ok = Imap.uid_delete(conn, 7)
    assert :ok = Imap.logout(conn)
    assert_receive {:fake_imap_done, :ok}
  end

  test "NO and BAD become errors" do
    {port, _} =
      FakeImap.start(
        FakeImap.login_steps() ++
          [
            {~r/^SELECT "Gibtsnicht"$/, ["TAG NO Mailbox doesn't exist"]},
            {~r/^UID SEARCH quatsch$/, ["TAG BAD Error in IMAP command"]}
          ]
      )

    {:ok, conn} = connect(port)
    assert {:error, {:no, "Mailbox doesn't exist"}} = Imap.select(conn, "Gibtsnicht")
    assert {:error, {:bad, _}} = Imap.uid_search(conn, "quatsch")
  end

  test "a failed login is an error" do
    {port, _} =
      FakeImap.start([{~r/^LOGIN/, ["TAG NO [AUTHENTICATIONFAILED] Authentication failed."]}])

    assert {:error, {:no, "[AUTHENTICATIONFAILED] Authentication failed."}} = connect(port)
  end

  test "refuses a server without MOVE" do
    {port, _} =
      FakeImap.start([
        {~r/^LOGIN/, ["TAG OK Logged in"]},
        {~r/^CAPABILITY$/, ["* CAPABILITY IMAP4rev1", "TAG OK"]}
      ])

    assert {:error, {:missing_capability, "MOVE"}} = connect(port)
  end

  test "a literal above the limit aborts before reading it" do
    {port, _} =
      FakeImap.start(
        FakeImap.login_steps() ++
          [{~r/^UID FETCH 1 \(BODY.PEEK\[\]\)$/, ["* 1 FETCH (UID 1 BODY[] {5000000}"]}]
      )

    {:ok, conn} = connect(port, max_literal: 1_000)
    assert {:error, :too_large} = Imap.uid_fetch(conn, 1)
  end

  test "a silent server times out" do
    {port, _} = FakeImap.start(FakeImap.login_steps() ++ [{~r/^NOOP$/, :hang}])
    {:ok, conn} = connect(port, timeout: 200)
    assert {:error, :timeout} = Imap.command(conn, "NOOP")
  end

  test "refuses non-ASCII strings instead of sending them" do
    {port, _} = FakeImap.start(FakeImap.login_steps())
    {:ok, conn} = connect(port)
    assert_raise ArgumentError, fn -> Imap.select(conn, "Entwürfe") end
  end
end
