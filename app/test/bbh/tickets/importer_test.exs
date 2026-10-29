defmodule Bbh.Tickets.ImporterTest do
  use Bbh.DataCase, async: false

  import Bbh.AccountsFixtures
  import Bbh.TicketsFixtures

  alias Bbh.Accounts.Scope
  alias Bbh.Tickets
  alias Bbh.Tickets.{Attachment, Importer, Message, Ticket}

  defp mail(opts) do
    headers =
      [
        {"X-Original-To", opts[:original_to] || "vorstand@buterland-beckerhook.de"},
        {"Delivered-To", "tickets@buterland-beckerhook.de"},
        {"From", opts[:from] || "Jürgen Müller <juergen@example.com>"},
        {"To", opts[:to] || "vorstand@buterland-beckerhook.de"},
        {"Subject", opts[:subject] || "Frage zum Zelt"},
        {"Message-ID", opts[:message_id] || "<#{System.unique_integer([:positive])}@example.com>"}
      ] ++ (opts[:headers] || [])

    head = Enum.map_join(headers, "\r\n", fn {k, v} -> "#{k}: #{v}" end)

    head <>
      "\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n" <>
      (opts[:body] || "Wann wird das Zelt aufgebaut?") <> "\r\n"
  end

  defp admin_scope, do: Scope.for_user(admin_user_fixture())

  setup do
    Application.put_env(:bbh, :ticket_imap, username: "tickets@buterland-beckerhook.de")
    on_exit(fn -> Application.delete_env(:bbh, :ticket_imap) end)
  end

  test "a new mail becomes a ticket in the queue it was sent to" do
    assert {:created, ticket} =
             Importer.import(
               mail(to: "vorstand@buterland-beckerhook.de, offiziere@buterland-beckerhook.de"),
               %{imap_mailbox: "INBOX", imap_uidvalidity: 1, imap_uid: 5}
             )

    assert %{queue: "vorstand", kind: "email", status: "new"} = ticket

    {:ok, loaded} = Tickets.get_ticket(admin_scope(), ticket.number)
    assert loaded.subject == "Frage zum Zelt"
    assert loaded.requester_name == "Jürgen Müller"
    assert loaded.requester_email == "juergen@example.com"

    assert [
             %{direction: "in", body: "Wann wird das Zelt aufgebaut?", imap_uid: 5} = inbound,
             note
           ] =
             loaded.messages

    assert inbound.header_message_id =~ "@example.com>"
    assert note.direction == "system"
    assert note.body == "Auch adressiert an: Offiziere"
  end

  test "an unknown recipient lands in Allgemein" do
    assert {:created, %{queue: "info"}} =
             Importer.import(mail(original_to: "tickets@buterland-beckerhook.de"))
  end

  test "the same mail twice is one ticket" do
    raw = mail(message_id: "<once@example.com>")
    assert {:created, _} = Importer.import(raw)
    assert :duplicate = Importer.import(raw)
    assert Repo.aggregate(Ticket, :count) == 1
  end

  test "a high spam score files it as spam, unannounced" do
    assert {:created, %{status: "spam", spam_score: 9.5}} =
             Importer.import(mail(headers: [{"X-Rspamd-Score", "9.5"}]))
  end

  test "auto-replies, bulk mail, our own addresses and loops are ignored" do
    assert :ignored = Importer.import(mail(headers: [{"Auto-Submitted", "auto-replied"}]))
    assert :ignored = Importer.import(mail(headers: [{"Precedence", "bulk"}]))
    assert :ignored = Importer.import(mail(from: "info@buterland-beckerhook.de"))

    assert :ignored =
             Importer.import(mail(headers: [{"Delivered-To", "tickets@buterland-beckerhook.de"}]))

    assert Repo.aggregate(Ticket, :count) == 0
  end

  test "an answer to our reply is threaded into the ticket and reopens it" do
    user = user_fixture()
    scope = granted_scope(user, ["info"])
    ticket = ticket_fixture()
    {:ok, loaded} = Tickets.get_ticket(scope, ticket.number)
    {:ok, _} = Tickets.reply(scope, loaded, "Am Freitag.")
    ours = Repo.get_by!(Message, direction: "out").message_id

    raw =
      mail(
        from: "erika@example.com",
        subject: "Re: Ihre Anfrage",
        headers: [{"In-Reply-To", ours}]
      )

    assert {:appended, %{id: id, status: "open"}} = Importer.import(raw)
    assert id == ticket.id
  end

  test "a bounce of our reply leaves a note on the ticket" do
    user = user_fixture()
    scope = granted_scope(user, ["info"])
    ticket = ticket_fixture()
    {:ok, loaded} = Tickets.get_ticket(scope, ticket.number)
    {:ok, _} = Tickets.reply(scope, loaded, "Hallo")
    ours = Repo.get_by!(Message, direction: "out").message_id

    raw =
      mail(
        from: "MAILER-DAEMON@mail.example.com",
        subject: "Undelivered Mail Returned to Sender",
        body: "Your message #{ours} could not be delivered."
      )

    assert {:bounce, %{id: id}} = Importer.import(raw)
    assert id == ticket.id
    assert Repo.get_by!(Message, direction: "system").ticket_id == ticket.id

    # A bounce that names nothing of ours is just ignored.
    assert :ignored = Importer.import(mail(from: "MAILER-DAEMON@x.example", body: "nope"))
  end

  test "attachments are stored encrypted; too large ones are dropped with a note" do
    Application.put_env(:bbh, :ticket_max_attachment_mb, 1)
    on_exit(fn -> Application.delete_env(:bbh, :ticket_max_attachment_mb) end)

    small = Base.encode64("%PDF-1.4 klein")
    big = Base.encode64(:binary.copy("x", 1_100_000))

    raw =
      "From: a@example.com\r\nX-Original-To: info@buterland-beckerhook.de\r\nSubject: Anhang\r\n" <>
        "Message-ID: <att@example.com>\r\nMIME-Version: 1.0\r\nContent-Type: multipart/mixed; boundary=B\r\n\r\n" <>
        "--B\r\nContent-Type: text/plain\r\n\r\nSiehe Anhang\r\n" <>
        "--B\r\nContent-Type: application/pdf\r\nContent-Disposition: attachment; filename=\"klein.pdf\"\r\nContent-Transfer-Encoding: base64\r\n\r\n#{small}\r\n" <>
        "--B\r\nContent-Type: application/zip\r\nContent-Disposition: attachment; filename=\"gross.zip\"\r\nContent-Transfer-Encoding: base64\r\n\r\n#{big}\r\n" <>
        "--B--\r\n"

    assert {:created, ticket} = Importer.import(raw)

    [attachment] = Repo.all(Attachment)
    refute attachment.data_enc =~ "PDF"
    assert attachment.size == 14

    {:ok, loaded} = Tickets.get_ticket(admin_scope(), ticket.number)
    [inbound, note] = loaded.messages
    assert [%{filename: "klein.pdf", size: 14}] = inbound.attachments
    assert note.body =~ "„gross.zip“"
    assert note.body =~ "zu groß"
  end
end
