defmodule Bbh.Tickets.RequestersTest do
  use Bbh.DataCase, async: true

  import Bbh.AccountsFixtures
  import Bbh.TicketsFixtures

  alias Bbh.Accounts.Scope
  alias Bbh.Repo
  alias Bbh.Tickets
  alias Bbh.Tickets.{Requesters, Ticket}

  setup do
    admin = Scope.for_user(admin_user_fixture())
    # Queue grants alone don't make a requester request: those are admin-only.
    handler = granted_scope(user_fixture(), ["info"])

    first = ticket_fixture()
    second = ticket_fixture(subject: "Noch eine Frage")
    other = ticket_fixture(requester_email: "max@example.com")

    %{admin: admin, handler: handler, first: first, second: second, other: other}
  end

  describe "requester_tickets/2" do
    test "finds every ticket of the address, deleted ones too", %{admin: admin} = ctx do
      {:ok, _} = Tickets.delete_ticket(admin, ctx.second)

      assert {:ok, tickets} = Requesters.requester_tickets(admin, "erika@example.com")

      assert tickets |> Enum.map(& &1.id) |> Enum.sort() ==
               Enum.sort([ctx.first.id, ctx.second.id])

      assert Enum.all?(tickets, &(&1.requester_email == "erika@example.com"))
    end

    test "is refused without admin rights", %{handler: handler} do
      assert Requesters.requester_tickets(handler, "erika@example.com") == {:error, :unauthorized}
    end
  end

  describe "delete_requester_tickets/3" do
    test "soft-deletes the address's tickets and counts only those it deleted", ctx do
      {:ok, _} = Tickets.delete_ticket(ctx.admin, ctx.second)

      assert Requesters.delete_requester_tickets(ctx.admin, "erika@example.com") == {:ok, 1}

      assert Repo.get!(Ticket, ctx.first.id).deleted_at
      refute Repo.get!(Ticket, ctx.other.id).deleted_at
    end

    test "purges the address's tickets for good, deleted ones included", ctx do
      {:ok, _} = Tickets.delete_ticket(ctx.admin, ctx.second)

      assert Requesters.delete_requester_tickets(ctx.admin, "erika@example.com", purge: true) ==
               {:ok, 2}

      refute Repo.get(Ticket, ctx.first.id)
      refute Repo.get(Ticket, ctx.second.id)
      assert Repo.get(Ticket, ctx.other.id)
    end

    test "is refused without admin rights and deletes nothing", %{handler: handler} = ctx do
      assert Requesters.delete_requester_tickets(handler, "erika@example.com", purge: true) ==
               {:error, :unauthorized}

      refute Repo.get!(Ticket, ctx.first.id).deleted_at
    end
  end
end
