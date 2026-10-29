defmodule BbhWeb.Admin.TicketLiveTest do
  use BbhWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Bbh.AccountsFixtures
  import Bbh.TicketsFixtures

  alias Bbh.Tickets
  alias Bbh.Tickets.Ticket

  setup %{conn: conn} do
    user = user_fixture()
    granted_scope(user, ["info"])
    %{user: user, conn: log_in_user(conn, user, auth_method: "passkey")}
  end

  describe "access" do
    test "needs a passkey or TOTP session", %{user: user} do
      conn = log_in_user(build_conn(), user, auth_method: "magic_link")

      assert {:error, {:redirect, %{to: "/users/security"}}} = live(conn, ~p"/admin/postfach")
    end

    test "needs a queue grant", %{conn: _conn} do
      other = user_fixture()
      conn = log_in_user(build_conn(), other, auth_method: "passkey")

      assert {:error, {:redirect, %{to: "/admin", flash: %{"error" => msg}}}} =
               live(conn, ~p"/admin/postfach")

      assert msg =~ "Postfach"
    end

    test "the navigation shows the Postfach to granted users only", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/admin")
      assert html =~ ~s|href="/admin/postfach"|

      conn = log_in_user(build_conn(), user_fixture(), auth_method: "passkey")
      {:ok, _lv, html} = live(conn, ~p"/admin")
      refute html =~ ~s|href="/admin/postfach"|
    end
  end

  describe "list" do
    test "shows the granted queues' tickets with decrypted subjects", %{conn: conn} do
      mine = ticket_fixture(subject: "Vereinsheim mieten")
      _foreign = ticket_fixture(queue: "vorstand", subject: "Vorstandssache")

      {:ok, lv, html} = live(conn, ~p"/admin/postfach")
      assert html =~ "Vereinsheim mieten"
      assert html =~ Ticket.reference(mine)
      refute html =~ "Vorstandssache"
      assert html =~ "1 neu."

      # A new ticket shows up without a reload.
      ticket_fixture(subject: "Noch eine Frage")
      assert render(lv) =~ "Noch eine Frage"
    end

    test "filters by view", %{conn: conn, user: user} do
      ticket = ticket_fixture(subject: "Erledigte Frage")
      {:ok, _} = Tickets.set_status(Bbh.Accounts.Scope.for_user(user), ticket, "closed")

      {:ok, _lv, html} = live(conn, ~p"/admin/postfach")
      refute html =~ "Erledigte Frage"

      {:ok, _lv, html} = live(conn, ~p"/admin/postfach?ansicht=closed")
      assert html =~ "Erledigte Frage"
    end
  end

  describe "ticket" do
    test "shows the thread and logs the view", %{conn: conn} do
      ticket = ticket_fixture(body: "Gibt es noch Plätze im Festzelt?")

      {:ok, _lv, html} = live(conn, ~p"/admin/postfach/#{Ticket.reference(ticket)}")
      assert html =~ "Gibt es noch Plätze im Festzelt?"
      assert html =~ "erika@example.com"
      assert "viewed" in Enum.map(Tickets.list_events(ticket), & &1.action)
    end

    test "a ticket from another queue is not found", %{conn: conn} do
      foreign = ticket_fixture(queue: "vorstand")

      assert {:error, {:live_redirect, %{to: "/admin/postfach", flash: %{"error" => _}}}} =
               live(conn, ~p"/admin/postfach/#{Ticket.reference(foreign)}")
    end

    test "take, note and status", %{conn: conn, user: user} do
      ticket = ticket_fixture()
      {:ok, lv, _html} = live(conn, ~p"/admin/postfach/#{Ticket.reference(ticket)}")

      lv |> element("button", "Übernehmen") |> render_click()
      assert Bbh.Repo.get!(Ticket, ticket.id).assignee_id == user.id

      html = lv |> form("#note-form", note: %{body: "Rückruf erledigt"}) |> render_submit()
      assert html =~ "Rückruf erledigt"

      html =
        lv
        |> form("#status-form", status: %{status: "follow_up", follow_up_on: ""})
        |> render_submit()

      assert html =~ "Bitte ein Datum"

      lv
      |> form("#status-form", status: %{status: "follow_up", follow_up_on: "2026-12-01"})
      |> render_submit()

      assert %{status: "follow_up", follow_up_on: ~D[2026-12-01]} =
               Bbh.Repo.get!(Ticket, ticket.id)
    end

    test "shows a membership application in structure", %{user: user} do
      scope = granted_scope(user, ["mitgliedschaft"])
      conn = log_in_user(build_conn(), user, auth_method: "passkey")

      ticket =
        ticket_fixture(
          queue: "mitgliedschaft",
          kind: "membership",
          payload: %{
            "vorname" => "Max",
            "nachname" => "Mustermann",
            "iban" => "DE89370400440532013000",
            "sepa" => true,
            "flags" => ["Antragsteller ist 14 Jahre alt"]
          }
        )

      {:ok, lv, html} = live(conn, ~p"/admin/postfach/#{Ticket.reference(ticket)}")
      assert html =~ "Aufnahmeantrag"
      assert html =~ "DE89370400440532013000"
      assert html =~ "Antragsteller ist 14 Jahre alt"

      lv |> form("#member-number-form", member_number: "4711") |> render_submit()
      {:ok, loaded} = Tickets.get_ticket(scope, ticket.number)
      assert loaded.payload["member_number"] == "4711"
    end
  end

  test "the dashboard lists my tickets", %{conn: conn, user: user} do
    {:ok, _} =
      Tickets.take(Bbh.Accounts.Scope.for_user(user), ticket_fixture(subject: "Meine Sache"))

    {:ok, _lv, html} = live(conn, ~p"/admin")
    assert html =~ "Meine Sache"
  end
end
