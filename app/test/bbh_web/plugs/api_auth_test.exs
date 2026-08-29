defmodule BbhWeb.Plugs.ApiAuthTest do
  @moduledoc """
  The rate-limit branches of `BbhWeb.Plugs.ApiAuth`.

  Their own file, and `async: false`: `BbhWeb.RateLimit` is disabled in the test
  environment (`config/test.exs`) so it does not interfere with every other suite, and
  these tests have to switch it on globally for the duration. The buckets live in a shared
  ETS table, so a concurrent test could otherwise consume the budget under test.
  """
  use BbhWeb.ConnCase, async: false

  import Bbh.AccountsFixtures

  alias Bbh.ApiTokens
  alias BbhWeb.RateLimit

  @window :timer.minutes(1)
  @ip_limit 300
  @token_limit 120

  setup do
    previous = Application.get_env(:bbh, RateLimit, [])
    Application.put_env(:bbh, RateLimit, Keyword.put(previous, :enabled, true))
    on_exit(fn -> Application.put_env(:bbh, RateLimit, previous) end)

    user = admin_user_fixture()
    {:ok, plaintext, token} = ApiTokens.create_pat(user, "test", ["mcp:read", "mcp:write"])

    # A distinct client IP per test, so the shared per-IP bucket from one test cannot
    # spill into the next within the same one-minute window.
    %{token: token, bearer: plaintext, ip: "198.51.100.#{System.unique_integer([:positive])}"}
  end

  defp ping(conn, bearer, ip) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer #{bearer}")
    |> put_req_header("x-forwarded-for", ip)
    |> post(~p"/mcp", Jason.encode!(%{jsonrpc: "2.0", id: 1, method: "ping"}))
  end

  # Burn a bucket down to its limit directly in ETS rather than by issuing hundreds of
  # HTTP requests — same bucket, same key format as `RateLimit.check/4` builds.
  defp exhaust(action, identifier, limit) do
    Enum.each(1..limit, fn _ -> RateLimit.hit("#{action}:#{identifier}", @window, limit) end)
  end

  test "lets an ordinary request through while the limiter is on", %{
    conn: conn,
    bearer: bearer,
    ip: ip
  } do
    assert json_response(ping(conn, bearer, ip), 200)
  end

  test "answers 429 with Retry-After once the per-token budget is spent", %{
    conn: conn,
    bearer: bearer,
    token: token,
    ip: ip
  } do
    exhaust("mcp", token.id, @token_limit)

    result = ping(conn, bearer, ip)

    assert json_response(result, 429)["error"] == "rate_limited"
    assert [retry_after] = get_resp_header(result, "retry-after")
    assert String.to_integer(retry_after) > 0
  end

  test "answers 429 once the per-IP budget is spent, before any token lookup", %{
    conn: conn,
    ip: ip
  } do
    exhaust("mcp_ip", ip, @ip_limit)

    # No credential at all: the IP guard must fire ahead of authentication, which is the
    # whole point — it is what stops an anonymous flood from hashing tokens against the DB.
    result =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-forwarded-for", ip)
      |> post(~p"/mcp", Jason.encode!(%{jsonrpc: "2.0", id: 1, method: "ping"}))

    assert json_response(result, 429)["error"] == "rate_limited"
  end

  test "one token's budget does not affect another's", %{conn: conn, token: token, ip: ip} do
    other_user = admin_user_fixture()
    {:ok, other_bearer, _} = ApiTokens.create_pat(other_user, "other", ["mcp:read"])

    exhaust("mcp", token.id, @token_limit)

    assert json_response(ping(conn, other_bearer, ip), 200)
  end
end
