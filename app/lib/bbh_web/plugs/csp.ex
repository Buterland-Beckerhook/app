defmodule BbhWeb.Plugs.CSP do
  @moduledoc """
  Sets a per-request Content-Security-Policy with a script nonce.

  Uses `'nonce-…' 'strict-dynamic'` for scripts: only the nonced tags in the
  root layout run, and any scripts they load are trusted transitively. The
  nonce is exposed as `@csp_nonce` for the layout.

  Disabled in development (see `config/dev.exs`) so Phoenix LiveReload keeps
  working; the nonce assign is still set so templates render unchanged.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    nonce = :crypto.strong_rand_bytes(16) |> Base.encode64(padding: false)
    conn = assign(conn, :csp_nonce, nonce)

    if enabled?() do
      put_resp_header(conn, "content-security-policy", policy(nonce))
    else
      conn
    end
  end

  @doc """
  Widens `form-action` on this response by the origin of `uri`.

  Browsers apply `form-action` to every redirect a form submission follows, not just
  to its `action`. The OAuth consent form posts to us and we answer with a redirect to
  the client's `redirect_uri` (e.g. `https://claude.ai/api/mcp/auth_callback`); with
  `form-action 'self'` alone Chrome refuses that last hop. Call this only with a URI
  that has been validated against the client's registration — whatever is passed here
  becomes a legitimate form destination for the page.
  """
  def allow_form_action(conn, uri) when is_binary(uri) do
    case {enabled?(), origin(uri)} do
      {true, origin} when is_binary(origin) ->
        put_resp_header(
          conn,
          "content-security-policy",
          policy(conn.assigns.csp_nonce, [origin])
        )

      _ ->
        conn
    end
  end

  # scheme://host[:port], or nil for anything that is not an absolute http(s) URI.
  defp origin(uri) do
    case URI.parse(uri) do
      %URI{scheme: scheme, host: host, port: port}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        if port == URI.default_port(scheme),
          do: "#{scheme}://#{host}",
          else: "#{scheme}://#{host}:#{port}"

      _ ->
        nil
    end
  end

  defp enabled?, do: Application.get_env(:bbh, __MODULE__, [])[:enabled] != false

  defp policy(nonce, form_actions \\ []) do
    [
      "default-src 'self'",
      "base-uri 'self'",
      "frame-ancestors 'self'",
      "object-src 'none'",
      "img-src 'self' data: blob:",
      "style-src 'self' 'unsafe-inline'",
      "font-src 'self' data:",
      "script-src 'nonce-#{nonce}' 'strict-dynamic'",
      # Altcha solves its proof of work in an inline blob Web Worker.
      "worker-src 'self' blob:",
      "connect-src 'self'",
      Enum.join(["form-action 'self'" | form_actions], " ")
    ]
    |> Enum.join("; ")
  end
end
