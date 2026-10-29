defmodule BbhWeb.Admin.TicketPdfControllerTest do
  # Not async: one test points :typst_bin at a missing binary.
  use BbhWeb.ConnCase, async: false

  import Bbh.AccountsFixtures
  import Bbh.TicketsFixtures

  alias Bbh.Tickets
  alias Bbh.Tickets.Ticket

  @payload %{
    "vorname" => "Erika",
    "nachname" => "Musterfrau",
    "strasse" => "Musterweg 1",
    "plz" => "48599",
    "ort" => "Gronau",
    "geburtsdatum" => "12.04.1988",
    "email" => "erika@example.com",
    "children" => [%{"vorname" => "Max", "geburtsdatum" => "01.02.2018"}],
    "kontoinhaber" => "Erika Musterfrau",
    "iban" => "DE89370400440532013000",
    "bic" => "COBADEFFXXX",
    "kreditinstitut" => "Commerzbank",
    "sepa" => true,
    "sepa_mandate" => true,
    "flags" => [],
    "submitted_at" => "2026-10-29T15:00:00Z",
    "client_ip" => "203.0.113.7",
    "form_version" => "abcdef012345",
    "altcha_verified" => true
  }

  setup do
    user = user_fixture()
    granted_scope(user, ["mitgliedschaft"])
    ticket = ticket_fixture(queue: "mitgliedschaft", kind: "membership", payload: @payload)
    %{user: user, ticket: ticket}
  end

  defp pdf_path(ticket), do: ~p"/admin/postfach/#{Ticket.reference(ticket)}/antrag.pdf"

  test "streams the PDF without caching and logs the export", %{user: user, ticket: ticket} do
    conn = build_conn() |> log_in_user(user, auth_method: "passkey") |> get(pdf_path(ticket))

    assert <<"%PDF", _::binary>> = response(conn, 200)
    assert get_resp_header(conn, "content-type") == ["application/pdf"]
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ "Aufnahmeantrag-#{Ticket.reference(ticket)}.pdf"
    refute disposition =~ "Musterfrau"
    assert "pdf_exported" in Enum.map(Tickets.list_events(ticket), & &1.action)
  end

  test "needs a strong session", %{user: user, ticket: ticket} do
    conn = build_conn() |> log_in_user(user, auth_method: "magic_link") |> get(pdf_path(ticket))
    assert redirected_to(conn) == ~p"/users/security"
  end

  test "is not found for a queue the user does not work", %{ticket: ticket} do
    other = user_fixture()
    granted_scope(other, ["info"])
    conn = build_conn() |> log_in_user(other, auth_method: "passkey") |> get(pdf_path(ticket))
    assert response(conn, 404)
  end

  test "is not found for a contact ticket", %{user: user} do
    granted_scope(user, ["info", "mitgliedschaft"])
    contact = ticket_fixture()
    conn = build_conn() |> log_in_user(user, auth_method: "passkey") |> get(pdf_path(contact))
    assert response(conn, 404)
  end

  test "data/2 fills the template's fields", %{user: user, ticket: ticket} do
    admin = Bbh.Accounts.Scope.for_user(admin_user_fixture())
    {:ok, loaded} = Tickets.get_ticket(admin, ticket.number)
    data = Bbh.Tickets.Pdf.data(loaded, user)

    assert data.iban == "DE89 3704 0044 0532 0130 00"
    assert data.mandate_reference == "gleich Mitgliedsnummer"
    assert data.submitted_at =~ "29.10.2026"
    assert data.mandate_text == Bbh.Membership.mandate_text()
    assert data.generated_by == user.email

    {:ok, numbered} = Tickets.set_member_number(admin, loaded, "4711")
    assert Bbh.Tickets.Pdf.data(numbered, user).mandate_reference == "4711"
  end

  test "a missing typst binary is an error, not a crash", %{user: user, ticket: ticket} do
    Application.put_env(:bbh, :typst_bin, "/nonexistent/typst")
    on_exit(fn -> Application.delete_env(:bbh, :typst_bin) end)

    admin = Bbh.Accounts.Scope.for_user(admin_user_fixture())
    {:ok, loaded} = Tickets.get_ticket(admin, ticket.number)

    assert {:error, {:typst_missing, :enoent}} =
             Bbh.Tickets.Pdf.membership_application(loaded, user)

    conn = build_conn() |> log_in_user(user, auth_method: "passkey") |> get(pdf_path(ticket))
    assert redirected_to(conn) =~ "/admin/postfach/"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "PDF konnte nicht erzeugt werden"
  end

  test "leaves no temp files behind", %{user: user, ticket: ticket} do
    before = File.ls!(System.tmp_dir!()) |> Enum.filter(&String.starts_with?(&1, "bbh-pdf-"))
    build_conn() |> log_in_user(user, auth_method: "passkey") |> get(pdf_path(ticket))
    after_ = File.ls!(System.tmp_dir!()) |> Enum.filter(&String.starts_with?(&1, "bbh-pdf-"))
    assert after_ -- before == []
  end
end
