defmodule BbhWeb.Admin.TicketAttachmentControllerTest do
  use BbhWeb.ConnCase, async: false

  import Bbh.AccountsFixtures
  import Bbh.TicketsFixtures

  alias Bbh.Tickets
  alias Bbh.Tickets.{Attachment, Ticket}
  alias BbhWeb.Admin.TicketAttachmentController

  @raw "From: a@example.com\r\nX-Original-To: info@buterland-beckerhook.de\r\nSubject: Anhang\r\n" <>
         "Message-ID: <dl@example.com>\r\nMIME-Version: 1.0\r\nContent-Type: multipart/mixed; boundary=B\r\n\r\n" <>
         "--B\r\nContent-Type: text/plain\r\n\r\nSiehe Anhang\r\n" <>
         "--B\r\nContent-Type: text/html\r\nContent-Disposition: attachment; filename=\"../böse \\\"datei\\\".html\"\r\n\r\n<script>alert(1)</script>\r\n" <>
         "--B--\r\n"

  setup do
    {:created, ticket} = Tickets.Importer.import(@raw)
    attachment = Bbh.Repo.one!(Attachment)
    user = user_fixture()
    granted_scope(user, ["info"])
    %{ticket: ticket, attachment: attachment, user: user}
  end

  defp attachment_path(ticket, attachment),
    do: ~p"/admin/postfach/#{Ticket.reference(ticket)}/anhang/#{attachment.id}"

  test "downloads as an opaque attachment and logs it", %{
    ticket: ticket,
    attachment: a,
    user: user
  } do
    conn =
      build_conn() |> log_in_user(user, auth_method: "passkey") |> get(attachment_path(ticket, a))

    assert response(conn, 200) =~ "<script>"
    assert get_resp_header(conn, "content-type") == ["application/octet-stream"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ ~s(attachment; filename="bose datei.html")
    refute disposition =~ ".."
    assert "attachment_downloaded" in Enum.map(Tickets.list_events(ticket), & &1.action)
  end

  test "needs a strong session and access to the queue", %{
    ticket: ticket,
    attachment: a,
    user: user
  } do
    conn =
      build_conn()
      |> log_in_user(user, auth_method: "magic_link")
      |> get(attachment_path(ticket, a))

    assert redirected_to(conn) == ~p"/users/security"

    other = user_fixture()
    granted_scope(other, ["vorstand"])

    conn =
      build_conn()
      |> log_in_user(other, auth_method: "passkey")
      |> get(attachment_path(ticket, a))

    assert response(conn, 404)
  end

  test "an attachment of another ticket is not found through this one", %{
    attachment: a,
    user: user
  } do
    other = ticket_fixture()

    conn =
      build_conn() |> log_in_user(user, auth_method: "passkey") |> get(attachment_path(other, a))

    assert response(conn, 404)

    conn =
      build_conn()
      |> log_in_user(user, auth_method: "passkey")
      |> get(~p"/admin/postfach/#{Ticket.reference(other)}/anhang/kein-uuid")

    assert response(conn, 404)
  end

  test "disposition/1 keeps the UTF-8 name and a safe ASCII fallback" do
    assert TicketAttachmentController.disposition("Anhäng.pdf") ==
             ~s(attachment; filename="Anhang.pdf"; filename*=UTF-8''Anh%C3%A4ng.pdf)

    assert TicketAttachmentController.disposition("a\r\nb;c.txt") ==
             ~s(attachment; filename="ab_c.txt"; filename*=UTF-8''ab%3Bc.txt)

    assert TicketAttachmentController.disposition(nil) =~ ~s(filename="anhang")
  end
end
