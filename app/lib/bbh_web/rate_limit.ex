defmodule BbhWeb.RateLimit do
  @moduledoc """
  Shared rate limiter for auth flows and public write endpoints.

  Backed by Hammer's ETS backend. The limiter process is started in the
  application supervision tree. Rate limiting is disabled in the test
  environment (see `config/test.exs`) so it does not interfere with tests.

  Buckets are keyed by an action plus a client identifier (usually the
  remote IP), e.g. `"login:203.0.113.7"`.
  """
  use Hammer, backend: :ets

  @doc """
  Checks the bucket for `action`/`identifier`.

  Returns `:ok` when the request is allowed, or `{:error, retry_after_ms}`
  when the limit for the window has been exceeded. When disabled (test env)
  it always returns `:ok`.

    * `limit` — max requests allowed within the window
    * `scale_ms` — window size in milliseconds
  """
  def check(action, identifier, limit, scale_ms)
      when is_binary(action) and is_integer(limit) and is_integer(scale_ms) do
    if enabled?() do
      key = "#{action}:#{normalize(identifier)}"

      case hit(key, scale_ms, limit) do
        {:allow, _count} -> :ok
        {:deny, retry_after_ms} -> {:error, retry_after_ms}
      end
    else
      :ok
    end
  end

  @doc """
  Best-effort client IP string for use in rate-limit keys.

  The app runs behind a trusted reverse proxy (Traefik/Caddy) that sets
  `x-forwarded-for`; the left-most entry is the originating client. Falls back
  to the socket peer address when the header is absent (e.g. direct access).
  """
  def client_ip(%Plug.Conn{} = conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [value | _] when is_binary(value) ->
        value |> String.split(",") |> List.first() |> String.trim()

      _ ->
        normalize(conn.remote_ip)
    end
  end

  defp normalize(ip) when is_tuple(ip), do: ip |> :inet.ntoa() |> to_string()
  defp normalize(other), do: to_string(other)

  defp enabled?, do: Application.get_env(:bbh, __MODULE__, [])[:enabled] != false
end
