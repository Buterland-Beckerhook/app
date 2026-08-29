defmodule BbhWeb.Api.MCPController do
  @moduledoc """
  Streamable HTTP transport for the MCP endpoint.

  Everything protocol-shaped lives in `BbhWeb.MCP.Server`; this only turns a message into
  an HTTP response. Requests are answered as a single `application/json` object rather
  than an SSE stream, and no session is issued — both are choices the transport explicitly
  allows, and together they are what keeps the endpoint stateless.

  `GET` and `DELETE` therefore answer `405`: the first would open a server-to-client
  stream this server never writes to, the second would end a session that does not exist.
  """
  use BbhWeb, :controller

  alias BbhWeb.MCP
  alias BbhWeb.MCP.Server

  # sobelow_skip ["XSS.SendResp"]
  # The body is Jason-encoded JSON sent as application/json, never interpreted as markup.
  def create(conn, _params) do
    with :ok <- check_version(conn) do
      scope = conn.assigns.current_scope
      api_token = conn.assigns.api_token

      case Server.handle(body(conn), scope, api_token) do
        {:reply, response} -> send_json(conn, :ok, response)
        :accepted -> send_resp(conn, :accepted, "")
        {:error, response} -> send_json(conn, :bad_request, response)
      end
    end
  end

  @doc """
  Answers the `GET` the transport defines on the MCP endpoint.

  `405` is the documented way to say "no server-initiated stream here"; clients handle it
  and fall back to plain request/response.
  """
  def no_stream(conn, _params), do: method_not_allowed(conn)

  @doc """
  Answers `DELETE` (end the session) and the CORS preflight `OPTIONS`.

  This server issues no `Mcp-Session-Id`, so there is no session to end. The preflight
  never reaches here — `BbhWeb.Plugs.CORS` halts it with `204` first.

  Kept separate from `no_stream/2` on purpose: sharing one action between a `GET` and a
  `DELETE` route is what Sobelow's `Config.CSRFRoute` check looks for, and silencing that
  check for the whole router would cost more than these three lines.
  """
  def no_session(conn, _params), do: method_not_allowed(conn)

  defp method_not_allowed(conn) do
    conn
    |> put_resp_header("allow", "POST, OPTIONS")
    |> send_json(:method_not_allowed, %{
      jsonrpc: "2.0",
      id: nil,
      error: %{code: -32600, message: "This endpoint only accepts POST."}
    })
  end

  # Plug.Parsers decodes the JSON body ahead of us. A top-level array — a JSON-RPC batch,
  # which the protocol removed — arrives wrapped under "_json"; unwrap it so the server
  # rejects it as the list it is rather than as a stray map.
  defp body(conn) do
    case conn.body_params do
      %{"_json" => value} -> value
      params -> params
    end
  end

  # The transport requires a 400 for a version we do not speak. A missing header is fine:
  # it means the pre-negotiation `initialize` call, or an older client.
  defp check_version(conn) do
    case get_req_header(conn, "mcp-protocol-version") do
      [version | _] when version not in [""] ->
        if version in MCP.supported_versions() do
          :ok
        else
          send_json(conn, :bad_request, %{
            jsonrpc: "2.0",
            id: nil,
            error: %{
              code: -32600,
              message:
                "Unsupported MCP-Protocol-Version #{version}. " <>
                  "Supported: #{Enum.join(MCP.supported_versions(), ", ")}."
            }
          })
        end

      _ ->
        :ok
    end
  end

  # sobelow_skip ["XSS.SendResp"]
  # Jason-encoded JSON with an explicit application/json content type.
  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
