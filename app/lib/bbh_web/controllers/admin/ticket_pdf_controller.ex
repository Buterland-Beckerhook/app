defmodule BbhWeb.Admin.TicketPdfController do
  @moduledoc """
  Download of a membership application as PDF (`Bbh.Tickets.export_pdf/2`). Behind a
  passkey/TOTP session like the rest of the Postfach; the PDF is generated per request
  and never cached or stored.
  """
  use BbhWeb, :controller

  import BbhWeb.ControllerHelpers, only: [not_found: 1]

  require Logger

  alias Bbh.Tickets
  alias Bbh.Tickets.Ticket

  plug :require_strong_auth

  # The body is a PDF sent as an attachment with nosniff — never rendered as HTML.
  # sobelow_skip ["XSS.SendResp"]
  def show(conn, %{"ref" => ref}) do
    scope = conn.assigns.current_scope

    with {:ok, %Ticket{kind: "membership"} = ticket} <- Tickets.get_ticket(scope, ref),
         {:ok, pdf} <- Tickets.export_pdf(scope, ticket) do
      conn
      |> put_resp_content_type("application/pdf", nil)
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("x-content-type-options", "nosniff")
      # The reference only — a name in the file name would end up in download folders
      # and browser histories.
      |> put_resp_header(
        "content-disposition",
        ~s(attachment; filename="Aufnahmeantrag-#{Ticket.reference(ticket)}.pdf")
      )
      |> send_resp(200, pdf)
    else
      {:error, reason} when reason in [:not_found, :unauthorized] ->
        not_found(conn)

      {:ok, %Ticket{}} ->
        not_found(conn)

      {:error, reason} ->
        # No inspect of the data — only what failed.
        Logger.error("Membership PDF failed: #{inspect(error_kind(reason))}")

        conn
        |> put_flash(:error, "Das PDF konnte nicht erzeugt werden.")
        |> redirect(to: ~p"/admin/postfach/#{ref}")
    end
  end

  defp error_kind({:typst, status, output}), do: {:typst, status, String.slice(output, 0, 500)}
  defp error_kind(other), do: other

  defp require_strong_auth(conn, _opts), do: BbhWeb.UserAuth.require_strong_auth(conn, [])
end
