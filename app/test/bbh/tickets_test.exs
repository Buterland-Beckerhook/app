defmodule Bbh.TicketsTest do
  use Bbh.DataCase, async: true

  import Bbh.AccountsFixtures
  import Bbh.TicketsFixtures

  alias Bbh.Accounts.Scope
  alias Bbh.Tickets
  alias Bbh.Tickets.{Event, Message, Ticket}

  setup do
    user = user_fixture()
    %{scope: granted_scope(user, ["info"]), user: user}
  end

  describe "create_ticket/2" do
    test "stores personal data encrypted only" do
      ticket = ticket_fixture()

      raw = Repo.get!(Ticket, ticket.id)
      refute raw.subject_enc =~ "Schützenfest"
      refute raw.requester_email_enc =~ "erika"
      assert raw.requester_email_hmac == Bbh.Vault.blind_index("Erika@example.com")

      [message] = Repo.all(Message)
      assert message.direction == "in"
      refute message.body_enc =~ "Schützenfest"

      %{rows: rows} = Repo.query!("SELECT * FROM tickets")
      refute inspect(rows) =~ "Erika"
    end

    test "numbers tickets and logs the creation" do
      a = ticket_fixture()
      b = ticket_fixture()
      assert b.number == a.number + 1
      assert Ticket.reference(a) =~ ~r/^BB-\d{4}-\d{4}$/
      assert Repo.get_by!(Event, ticket_id: a.id).action == "created"
    end

    test "refuses an unknown queue" do
      assert {:error, %Ecto.Changeset{}} =
               Tickets.create_ticket(%{queue: "kegeln", kind: "contact"}, %{body: "x"})
    end
  end

  describe "list_tickets/2 and get_ticket/2" do
    test "shows only granted queues and decrypts the subject", %{scope: scope} do
      mine = ticket_fixture()
      _other = ticket_fixture(queue: "mitgliedschaft", kind: "membership")

      assert %{entries: [entry], total: 1} = Tickets.list_tickets(scope)
      assert entry.id == mine.id
      assert entry.subject == "Frage zum Schützenfest"
      assert Tickets.count_new(scope) == 1
    end

    test "admins see every queue" do
      ticket_fixture()
      ticket_fixture(queue: "mitgliedschaft", kind: "membership")
      admin_scope = Scope.for_user(admin_user_fixture())
      assert Tickets.list_tickets(admin_scope).total == 2
    end

    test "get_ticket decrypts the thread and hides foreign queues", %{scope: scope} do
      ticket = ticket_fixture()
      foreign = ticket_fixture(queue: "vorstand")

      assert {:ok, loaded} = Tickets.get_ticket(scope, Ticket.reference(ticket))
      assert loaded.requester_email == "erika@example.com"
      assert [%{body: "Wann ist das nächste Schützenfest?"}] = loaded.messages

      assert Tickets.get_ticket(scope, foreign.number) == {:error, :not_found}
      assert Tickets.get_ticket(scope, "BB-2026-9999") == {:error, :not_found}
      assert Tickets.get_ticket(scope, "unsinn") == {:error, :not_found}
    end

    test "views: mine, closed, spam, overdue", %{scope: scope} do
      taken = ticket_fixture()
      {:ok, _} = Tickets.take(scope, taken)
      closed = ticket_fixture()
      {:ok, _} = Tickets.set_status(scope, closed, "closed")
      spam = ticket_fixture()
      {:ok, _} = Tickets.mark_spam(scope, spam)
      due = ticket_fixture()
      {:ok, _} = Tickets.set_status(scope, due, "follow_up", Date.add(Date.utc_today(), -1))
      stale = ticket_fixture()

      Repo.update_all(from(t in Ticket, where: t.id == ^stale.id),
        set: [inserted_at: DateTime.add(DateTime.utc_now(:second), -2, :day)]
      )

      ids = fn view -> Tickets.list_tickets(scope, view: view).entries |> Enum.map(& &1.id) end

      assert ids.("mine") == [taken.id]
      assert ids.("closed") == [closed.id]
      assert ids.("spam") == [spam.id]
      assert Enum.sort(ids.("overdue")) == Enum.sort([due.id, stale.id])
      refute closed.id in ids.("all")
      assert taken.id in ids.("all")
      # "Offen" is what nobody has taken yet.
      refute taken.id in ids.("open")
      assert stale.id in ids.("open")

      assert Tickets.count_views(scope) == %{"open" => 2, "mine" => 1, "overdue" => 2}
      # A queue filter the scope may not see is ignored, not an empty result.
      assert Tickets.count_views(scope, "vorstand") == Tickets.count_views(scope, "info")
    end
  end

  describe "working a ticket" do
    test "take assigns and opens", %{scope: scope, user: user} do
      {:ok, ticket} = Tickets.take(scope, ticket_fixture())
      assert ticket.assignee_id == user.id
      assert ticket.status == "open"
    end

    test "only users who can see the queue are assignable", %{scope: scope} do
      ticket = ticket_fixture()
      outsider = user_fixture()
      assert Tickets.assign(scope, ticket, outsider.id) == {:error, :invalid_assignee}

      admin = admin_user_fixture()
      assert {:ok, %{assignee_id: id}} = Tickets.assign(scope, ticket, admin.id)
      assert id == admin.id
    end

    test "follow-up needs a date; closing stamps closed_at", %{scope: scope} do
      ticket = ticket_fixture()
      assert {:error, %Ecto.Changeset{}} = Tickets.set_status(scope, ticket, "follow_up", "")
      assert {:ok, t} = Tickets.set_status(scope, ticket, "follow_up", "2026-12-01")
      assert t.follow_up_on == ~D[2026-12-01]
      assert {:ok, t} = Tickets.set_status(scope, t, "closed")
      assert t.closed_at
      assert t.follow_up_on == nil
      assert {:ok, t} = Tickets.set_status(scope, t, "open")
      assert t.closed_at == nil
      assert Tickets.set_status(scope, t, "new") == {:error, :invalid_status}
    end

    test "notes are stored encrypted and logged", %{scope: scope, user: user} do
      ticket = ticket_fixture()
      assert {:ok, _} = Tickets.add_note(scope, ticket, "  Rückruf am Montag  ")
      assert Tickets.add_note(scope, ticket, "  ") == {:error, :empty}

      {:ok, loaded} = Tickets.get_ticket(scope, ticket.number)

      assert [_, %{direction: "note", body: "Rückruf am Montag", author_id: author}] =
               loaded.messages

      assert author == user.id
      assert "noted" in Enum.map(Tickets.list_events(ticket), & &1.action)
    end

    test "nothing works on a ticket outside the scope's queues", %{scope: scope} do
      foreign = ticket_fixture(queue: "vorstand")
      assert Tickets.take(scope, foreign) == {:error, :unauthorized}
      assert Tickets.add_note(scope, foreign, "x") == {:error, :unauthorized}
      assert Tickets.set_status(scope, foreign, "closed") == {:error, :unauthorized}
    end

    test "moving to another queue drops the assignee", %{scope: scope} do
      {:ok, ticket} = Tickets.take(scope, ticket_fixture())
      assert {:ok, moved} = Tickets.move_queue(scope, ticket, "vorstand")
      assert moved.queue == "vorstand"
      assert moved.assignee_id == nil
      assert Tickets.move_queue(scope, moved, "info") == {:error, :unauthorized}
    end

    test "delete and restore are admin-only; deleted tickets disappear", %{scope: scope} do
      ticket = ticket_fixture()
      admin_scope = Scope.for_user(admin_user_fixture())

      assert Tickets.delete_ticket(scope, ticket) == {:error, :unauthorized}
      assert {:ok, deleted} = Tickets.delete_ticket(admin_scope, ticket)
      assert Tickets.get_ticket(scope, ticket.number) == {:error, :not_found}
      assert Tickets.list_tickets(scope).total == 0
      assert Tickets.list_tickets(admin_scope, view: "deleted").total == 1
      assert {:ok, _} = Tickets.restore_ticket(admin_scope, deleted)
      assert Tickets.list_tickets(scope).total == 1
    end

    test "the member number goes into the encrypted payload" do
      user = user_fixture()
      scope = granted_scope(user, ["mitgliedschaft"])

      ticket =
        ticket_fixture(
          queue: "mitgliedschaft",
          kind: "membership",
          payload: %{"vorname" => "Max"}
        )

      assert {:ok, _} = Tickets.set_member_number(scope, ticket, " 1234 ")
      {:ok, loaded} = Tickets.get_ticket(scope, ticket.number)
      assert loaded.payload == %{"vorname" => "Max", "member_number" => "1234"}
      assert Tickets.set_member_number(scope, ticket_fixture(), "1") == {:error, :not_membership}
    end

    test "a spam marking can be taken back", %{scope: scope} do
      {:ok, spam} = Tickets.mark_spam(scope, ticket_fixture())
      assert {:ok, %{status: "new"}} = Tickets.unmark_spam(scope, spam)

      {:ok, taken} = Tickets.take(scope, ticket_fixture())
      {:ok, spam} = Tickets.mark_spam(scope, taken)
      assert {:ok, %{status: "open"}} = Tickets.unmark_spam(scope, spam)
      assert Tickets.unmark_spam(scope, ticket_fixture()) == {:error, :not_spam}
      assert "unmarked_spam" in Enum.map(Tickets.list_events(spam), & &1.action)
    end

    test "views are logged at most once per ten minutes", %{scope: scope} do
      ticket = ticket_fixture()
      :ok = Tickets.record_view(scope, ticket)
      :ok = Tickets.record_view(scope, ticket)
      assert Enum.count(Tickets.list_events(ticket), &(&1.action == "viewed")) == 1
    end

    test "related tickets come from the same address", %{scope: scope} do
      a = ticket_fixture()
      b = ticket_fixture(requester_email: "ERIKA@example.com ")
      _c = ticket_fixture(requester_email: "max@example.com")

      assert Enum.map(Tickets.related_tickets(scope, a), & &1.id) == [b.id]
    end

    test "changes are broadcast", %{scope: scope} do
      Tickets.subscribe()
      ticket = ticket_fixture()
      assert_receive {:tickets_changed, id} when id == ticket.id
      {:ok, _} = Tickets.take(scope, ticket)
      assert_receive {:tickets_changed, ^id}
    end

    test "events never carry personal data", %{scope: scope} do
      ticket = ticket_fixture()
      {:ok, ticket} = Tickets.take(scope, ticket)
      {:ok, _} = Tickets.add_note(scope, ticket, "Erika ruft zurück")

      for event <- Tickets.list_events(ticket) do
        refute inspect(event.meta) =~ ~r/erika|Schützenfest/i
      end
    end
  end

  test "ticket structs do not leak clear text through inspect" do
    ticket = ticket_fixture()
    refute inspect(ticket) =~ "erika@example.com"
    refute inspect(ticket) =~ "Schützenfest"
  end
end
