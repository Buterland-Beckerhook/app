defmodule Bbh.Tickets.MembershipTest do
  # The PDF itself (typst) is covered by BbhWeb.Admin.TicketPdfControllerTest; this
  # covers what the context refuses before ever rendering one.
  use Bbh.DataCase, async: true

  import Bbh.AccountsFixtures
  import Bbh.TicketsFixtures

  alias Bbh.Tickets
  alias Bbh.Tickets.Membership

  setup do
    application =
      ticket_fixture(queue: "mitgliedschaft", kind: "membership", payload: %{"vorname" => "Max"})

    %{
      application: application,
      board: granted_scope(user_fixture(), ["mitgliedschaft"]),
      info_only: granted_scope(user_fixture(), ["info"])
    }
  end

  describe "export_pdf/2" do
    test "refuses a ticket that is no membership application", %{board: board} do
      assert Membership.export_pdf(board, ticket_fixture()) == {:error, :not_membership}
    end

    test "refuses a user without the membership queue", %{info_only: info_only} = ctx do
      assert Membership.export_pdf(info_only, ctx.application) == {:error, :unauthorized}
    end
  end

  describe "set_member_number/3" do
    test "refuses a user without the membership queue", %{info_only: info_only} = ctx do
      assert Membership.set_member_number(info_only, ctx.application, "4711") ==
               {:error, :unauthorized}

      {:ok, loaded} = Tickets.get_ticket(ctx.board, ctx.application.number)
      refute Map.has_key?(loaded.payload, "member_number")
    end

    test "refuses a deleted application", %{board: board} = ctx do
      admin = Bbh.Accounts.Scope.for_user(admin_user_fixture())
      {:ok, deleted} = Tickets.delete_ticket(admin, ctx.application)

      assert Membership.set_member_number(board, deleted, "4711") == {:error, :unauthorized}
    end
  end
end
