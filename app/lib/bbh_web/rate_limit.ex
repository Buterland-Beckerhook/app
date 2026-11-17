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

  @doc "Client IP string for use in rate-limit keys — see `BbhWeb.ClientIp`."
  defdelegate client_ip(conn), to: BbhWeb.ClientIp, as: :get

  defp normalize(ip) when is_tuple(ip), do: ip |> :inet.ntoa() |> to_string() |> normalize()

  # An IPv6 host usually holds a whole /64 and could rotate through it for a fresh
  # bucket per request, so a /64 shares one. IPv4-mapped addresses stay per address,
  # and anything that is not an IPv6 address (IPv4, a user id, an email) is kept as is.
  defp normalize(identifier) when is_binary(identifier) do
    case :inet.parse_ipv6strict_address(String.to_charlist(identifier)) do
      {:ok, {0, 0, 0, 0, 0, 0xFFFF, _, _}} -> identifier
      {:ok, {a, b, c, d, _, _, _, _}} -> "#{:inet.ntoa({a, b, c, d, 0, 0, 0, 0})}/64"
      {:error, _} -> identifier
    end
  end

  defp normalize(other), do: to_string(other)

  defp enabled?, do: Application.get_env(:bbh, __MODULE__, [])[:enabled] != false
end
