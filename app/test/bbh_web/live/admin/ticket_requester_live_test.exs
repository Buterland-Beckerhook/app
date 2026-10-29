defmodule BbhWeb.Admin.TicketRequesterLiveTest do
  use BbhWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Bbh.AccountsFixtures
  import Bbh.TicketsFixtures

  alias Bbh.Repo
  alias Bbh.Tickets.{Event, Ticket}

  setup %{conn: conn} do
    admin = admin_user_fixture()
    %{conn: log_in_user(conn, admin, auth_method: "passkey")}
  end

  test "finds every ticket of an address across queues, never via the URL", %{conn: conn} do
    a = ticket_fixture(subject: "Erste Frage")

    b =
      ticket_fixture(
        queue: "vorstand",
        subject: "Zweite Frage",
        requester_email: "ERIKA@example.com"
      )

    _other = ticket_fixture(requester_email: "max@example.com", subject: "Fremd")

    {:ok, lv, _} = live(conn, ~p"/admin/postfach/auskunft")
    html = lv |> form("#lookup-form", lookup: %{email: "erika@example.com"}) |> render_submit()

    assert html =~ "2 Anfrage(n) von erika@example.com"
    assert html =~ Ticket.reference(a)
    assert html =~ Ticket.reference(b)
    refute html =~ "Fremd"

    # Logged without the address.
    lookup = Repo.get_by!(Event, action: "requester_lookup")
    assert lookup.meta == %{"count" => 2}
  end

  test "soft-deletes all of them", %{conn: conn} do
    a = ticket_fixture()
    b = ticket_fixture(queue: "mitgliedschaft", kind: "membership")

    {:ok, lv, _} = live(conn, ~p"/admin/postfach/auskunft")
    lv |> form("#lookup-form", lookup: %{email: "erika@example.com"}) |> render_submit()
    html = lv |> element("button", "Alle löschen") |> render_click()

    assert html =~ "2 Anfrage(n) gelöscht"
    assert Repo.get!(Ticket, a.id).deleted_at
    assert Repo.get!(Ticket, b.id).deleted_at
  end

  test "purges them for good at once", %{conn: conn} do
    a = ticket_fixture()

    {:ok, lv, _} = live(conn, ~p"/admin/postfach/auskunft")
    lv |> form("#lookup-form", lookup: %{email: "erika@example.com"}) |> render_submit()
    html = lv |> element("button", "Sofort endgültig löschen") |> render_click()

    assert html =~ "1 Anfrage(n) endgültig gelöscht"
    refute Repo.get(Ticket, a.id)
    assert html =~ "Keine Anfragen von erika@example.com"
  end

  test "is for admins only" do
    user = user_fixture()
    granted_scope(user, ["info"])
    conn = log_in_user(build_conn(), user, auth_method: "passkey")

    assert {:error, {:live_redirect, %{to: "/admin/postfach"}}} =
             live(conn, ~p"/admin/postfach/auskunft")
  end

  test "needs a strong session" do
    conn = log_in_user(build_conn(), admin_user_fixture(), auth_method: "magic_link")

    assert {:error, {:redirect, %{to: "/users/security"}}} =
             live(conn, ~p"/admin/postfach/auskunft")
  end
end
