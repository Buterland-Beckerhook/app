defmodule BbhWeb.Admin.TicketAttachmentController do
  @moduledoc """
  Download of a mail attachment from the Postfach (`Bbh.Tickets.get_attachment/3`).

  Always a download, never shown: `application/octet-stream` whatever the mail claimed,
  `Content-Disposition: attachment` with a cleaned file name, `nosniff`, no caching.
  Behind a passkey/TOTP session; every download is in the ticket's history.
  """
  use BbhWeb, :controller

  import BbhWeb.ControllerHelpers, only: [not_found: 1]

  alias Bbh.Tickets

  plug :require_strong_auth

  # The body is an attachment of unknown content sent as an opaque download with
  # nosniff — never rendered.
  # sobelow_skip ["XSS.SendResp", "XSS.ContentType"]
  def show(conn, %{"ref" => ref, "id" => id}) do
    scope = conn.assigns.current_scope

    with {:ok, ticket} <- Tickets.get_ticket(scope, ref),
         {:ok, attachment} <- Tickets.get_attachment(scope, ticket, id) do
      conn
      |> put_resp_content_type("application/octet-stream", nil)
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("content-disposition", disposition(attachment.filename))
      |> send_resp(200, attachment.data)
    else
      _ -> not_found(conn)
    end
  end

  @doc false
  # An ASCII fallback plus the UTF-8 name (RFC 6266); no path parts, no quotes or
  # control characters that could break the header.
  def disposition(filename) do
    name =
      (filename || "anhang")
      |> String.split(["/", "\\"])
      |> List.last()
      |> String.replace(~r/[\x00-\x1f\x7f"]/, "")
      |> String.trim()
      |> case do
        "" -> "anhang"
        name -> name
      end

    ascii =
      name
      |> String.normalize(:nfd)
      |> String.replace(~r/[^\x20-\x7e]/, "")
      |> String.replace(";", "_")

    ascii = if ascii in ["", "."], do: "anhang", else: ascii

    ~s(attachment; filename="#{ascii}"; filename*=UTF-8''#{URI.encode(name, &URI.char_unreserved?/1)})
  end

  defp require_strong_auth(conn, _opts), do: BbhWeb.UserAuth.require_strong_auth(conn, [])
end
