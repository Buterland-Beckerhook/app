defmodule BbhWeb.Plugs.ApiAuth do
  @moduledoc """
  Authenticates an MCP request from its `Authorization: Bearer` header.

  On success the connection carries `:current_scope` — the very same
  `Bbh.Accounts.Scope` the admin LiveViews run on — plus the `:api_token` that produced
  it. Everything downstream authorizes through `BbhWeb.Authz` against that scope, so a
  token can never reach past what its owner may do.

  On failure it halts with `401` and a `WWW-Authenticate` challenge pointing at the
  protected-resource metadata, which is how an unauthenticated client discovers where to
  authorize. Every failure reason answers alike: a probing client must not be able to
  tell "no such token" from "expired" from "wrong audience".
  """
  import Plug.Conn

  alias Bbh.Accounts.Scope
  alias Bbh.ApiTokens
  alias BbhWeb.MCP
  alias BbhWeb.RateLimit

  require Logger

  @behaviour Plug

  # Generous per-IP ceiling so an unauthenticated flood cannot keep hashing tokens
  # against the database; the real budget is the per-token one below.
  @ip_limit 300
  @token_limit 120

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    with :ok <- rate_limit_ip(conn),
         {:ok, token} <- bearer_token(conn),
         {:ok, user, api_token} <- ApiTokens.verify(token, MCP.resource_uri()),
         :ok <- rate_limit_token(conn, api_token) do
      ApiTokens.touch(api_token)

      conn
      |> assign(:current_scope, Scope.for_user(user))
      |> assign(:api_token, api_token)
    else
      {:halt, conn} -> conn
      {:error, reason} -> unauthorized(conn, reason)
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> {:ok, String.trim(token)}
      ["bearer " <> token | _] -> {:ok, String.trim(token)}
      _ -> {:error, :missing}
    end
  end

  defp rate_limit_ip(conn) do
    case RateLimit.check("mcp_ip", RateLimit.client_ip(conn), @ip_limit, :timer.minutes(1)) do
      :ok -> :ok
      {:error, retry_after} -> {:halt, too_many_requests(conn, retry_after)}
    end
  end

  defp rate_limit_token(conn, api_token) do
    case RateLimit.check("mcp", api_token.id, @token_limit, :timer.minutes(1)) do
      :ok -> :ok
      {:error, retry_after} -> {:halt, too_many_requests(conn, retry_after)}
    end
  end

  defp unauthorized(conn, reason) do
    # Logged, never returned: the response is identical for every reason.
    Logger.info("MCP auth rejected: #{reason}")

    conn
    |> put_resp_header("www-authenticate", MCP.challenge(error: "invalid_token"))
    |> json_halt(:unauthorized, %{
      error: "invalid_token",
      error_description: "A valid bearer token is required."
    })
  end

  defp too_many_requests(conn, retry_after_ms) do
    conn
    |> put_resp_header("retry-after", to_string(div(retry_after_ms, 1000) + 1))
    |> json_halt(:too_many_requests, %{error: "rate_limited"})
  end

  defp json_halt(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
    |> halt()
  end
end
