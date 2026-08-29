defmodule BbhWeb.Plugs.CORS do
  @moduledoc """
  Permissive CORS for the MCP and OAuth endpoints, and only for those.

  Why allow-all is safe here, when it would not be on the browser pipeline: these routes
  read no cookie and no session. The only credential they accept is a bearer token in the
  `Authorization` header, which the browser will not attach on its own and which a
  cross-origin page has no way to obtain. A hostile page can therefore issue requests, but
  only unauthenticated ones — exactly what it could do from a server anyway.

  This is also why the transport spec's `Origin`-validation advice does not apply: that
  requirement targets DNS rebinding against *localhost* MCP servers, which authenticate
  ambiently and would otherwise act on a rebound attacker's behalf. See
  `docs/adr/0009-mcp-server.md`.

  Mounted in the `:mcp` / `:api_oauth` pipelines only; the browser pipeline is untouched.
  """
  import Plug.Conn

  @behaviour Plug

  @allowed_headers "authorization, content-type, mcp-protocol-version, mcp-session-id, last-event-id"
  @allowed_methods "GET, POST, DELETE, OPTIONS"

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: "OPTIONS"} = conn, _opts) do
    conn
    |> put_cors_headers()
    |> put_resp_header("access-control-max-age", "86400")
    |> send_resp(:no_content, "")
    |> halt()
  end

  def call(conn, _opts), do: put_cors_headers(conn)

  defp put_cors_headers(conn) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", @allowed_methods)
    |> put_resp_header("access-control-allow-headers", @allowed_headers)
    # Without this a browser client cannot read the session header or the challenge that
    # tells it how to authorize.
    |> put_resp_header("access-control-expose-headers", "mcp-session-id, www-authenticate")
  end
end
