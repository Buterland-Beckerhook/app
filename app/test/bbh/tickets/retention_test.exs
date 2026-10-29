defmodule Bbh.Tickets.RetentionTest do
  use Bbh.DataCase, async: false
  use Oban.Testing, repo: Bbh.Repo

  import Bbh.AccountsFixtures
  import Bbh.TicketsFixtures

  alias Bbh.Accounts.Scope
  alias Bbh.Tickets
  alias Bbh.Tickets.{Attachment, Event, Message, Retention, Ticket}

  defp set(ticket, fields) do
    Repo.update_all(from(t in Ticket, where: t.id == ^ticket.id), set: fields)
    Repo.get!(Ticket, ticket.id)
  end

  defp ago(days), do: DateTime.utc_now(:second) |> DateTime.add(-days, :day)

  setup do
    Application.delete_env(:bbh, :ticket_imap)
    %{scope: granted_scope(user_fixture(), ["info"])}
  end

  test "closed tickets are soft-deleted after the retention period", %{scope: scope} do
    {:ok, old} = Tickets.set_status(scope, ticket_fixture(), "closed")
    old = set(old, closed_at: ago(400))
    {:ok, recent} = Tickets.set_status(scope, ticket_fixture(), "closed")
    open = ticket_fixture() |> set(inserted_at: ago(400))

    assert %{soft_deleted: 1} = Retention.run()
    assert Repo.get!(Ticket, old.id).deleted_at
    refute Repo.get!(Ticket, recent.id).deleted_at
    refute Repo.get!(Ticket, open.id).deleted_at

    assert Enum.any?(
             Tickets.list_events(old),
             &(&1.action == "deleted" and &1.meta["reason"] == "retention")
           )
  end

  test "soft-deleted tickets are purged with everything in them; events keep the number" do
    raw =
      "From: a@example.com\r\nX-Original-To: info@buterland-beckerhook.de\r\nSubject: x\r\nMessage-ID: <r@example.com>\r\n" <>
        "MIME-Version: 1.0\r\nContent-Type: multipart/mixed; boundary=B\r\n\r\n--B\r\nContent-Type: text/plain\r\n\r\nText\r\n" <>
        "--B\r\nContent-Type: application/pdf\r\nContent-Disposition: attachment; filename=\"a.pdf\"\r\n\r\n%PDF\r\n--B--\r\n"

    {:created, ticket} = Tickets.Importer.import(raw)
    admin = Scope.for_user(admin_user_fixture())
    {:ok, deleted} = Tickets.delete_ticket(admin, ticket)

    # Within the grace period it stays, and can be restored.
    assert %{purged: 0} = Retention.run()
    assert Repo.get(Ticket, ticket.id)

    set(deleted, deleted_at: ago(31))
    assert %{purged: 1} = Retention.run()

    refute Repo.get(Ticket, ticket.id)
    assert Repo.aggregate(Message, :count) == 0
    assert Repo.aggregate(Attachment, :count) == 0

    events = Repo.all(from e in Event, where: e.ticket_number == ^ticket.number)
    assert Enum.all?(events, &is_nil(&1.ticket_id))
    actions = Enum.map(events, & &1.action)
    assert "created" in actions
    assert "deleted" in actions
    assert "purged" in actions
  end

  test "spam is purged after the purge period without a soft delete", %{scope: scope} do
    {:ok, spam} = Tickets.mark_spam(scope, ticket_fixture())
    {:ok, fresh_spam} = Tickets.mark_spam(scope, ticket_fixture())
    set(spam, last_activity_at: ago(31))

    assert %{purged: 1} = Retention.run()
    refute Repo.get(Ticket, spam.id)
    assert Repo.get(Ticket, fresh_spam.id)
  end

  test "old history is pruned" do
    ticket = ticket_fixture()

    Repo.update_all(from(e in Event, where: e.ticket_id == ^ticket.id),
      set: [inserted_at: ago(400)]
    )

    assert %{events: n} = Retention.run()
    assert n >= 1
    assert Tickets.list_events(ticket) == []
  end

  test "a ticket with a server copy is only purged once the copy is gone" do
    {:created, ticket} =
      Tickets.Importer.import(
        "From: a@example.com\r\nX-Original-To: info@buterland-beckerhook.de\r\nSubject: x\r\nMessage-ID: <c@example.com>\r\n\r\nText\r\n",
        %{imap_mailbox: "Tickets/Importiert", imap_uidvalidity: 1, imap_uid: 3}
      )

    admin = Scope.for_user(admin_user_fixture())
    {:ok, deleted} = Tickets.delete_ticket(admin, ticket)
    # Deleting queues the removal of the copy right away.
    assert_enqueued(
      worker: Bbh.Workers.ImapCleanup,
      args: %{ticket_id: ticket.id, action: "delete"}
    )

    set(deleted, deleted_at: ago(31))

    # An unreachable server keeps the ticket for the next night.
    Application.put_env(:bbh, :ticket_imap,
      host: "127.0.0.1",
      port: 1,
      tls: false,
      username: "x",
      password: "y"
    )

    on_exit(fn -> Application.delete_env(:bbh, :ticket_imap) end)
    assert %{purged: 0} = Retention.run()
    assert Repo.get(Ticket, ticket.id)

    # Without a mailbox configured there is nothing to wait for.
    Application.delete_env(:bbh, :ticket_imap)
    assert %{purged: 1} = Retention.run()
  end
end
