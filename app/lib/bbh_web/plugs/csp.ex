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

  defp enabled?, do: Application.get_env(:bbh, __MODULE__, [])[:enabled] != false

  defp policy(nonce) do
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
      "form-action 'self'"
    ]
    |> Enum.join("; ")
  end
end
