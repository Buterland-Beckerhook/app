defmodule BbhWeb.RateLimitTest do
  # async: false — turns the (globally disabled in test) rate limiter on.
  use ExUnit.Case, async: false

  alias BbhWeb.RateLimit

  setup do
    previous = Application.get_env(:bbh, RateLimit, [])
    Application.put_env(:bbh, RateLimit, Keyword.put(previous, :enabled, true))
    on_exit(fn -> Application.put_env(:bbh, RateLimit, previous) end)

    # A fresh action per test, so buckets never carry over.
    %{action: "test-#{System.unique_integer([:positive])}"}
  end

  test "IPv6 addresses in one /64 share a bucket", %{action: action} do
    assert :ok = RateLimit.check(action, "2001:db8:1:2::1", 2, 60_000)
    assert :ok = RateLimit.check(action, "2001:db8:1:2:aaaa:bbbb:cccc:dddd", 2, 60_000)
    assert {:error, _} = RateLimit.check(action, {0x2001, 0xDB8, 1, 2, 9, 9, 9, 9}, 2, 60_000)

    # The neighbouring /64 is someone else.
    assert :ok = RateLimit.check(action, "2001:db8:1:3::1", 2, 60_000)
  end

  test "IPv4, IPv4-mapped addresses and other identifiers stay per value", %{action: action} do
    for id <- ["203.0.113.7", "203.0.113.8", "::ffff:203.0.113.9", "::ffff:203.0.113.10"] do
      assert :ok = RateLimit.check(action, id, 1, 60_000)
    end

    assert :ok = RateLimit.check(action, Ecto.UUID.generate(), 1, 60_000)
    assert :ok = RateLimit.check(action, "erika@example.com", 1, 60_000)
    assert {:error, _} = RateLimit.check(action, "erika@example.com", 1, 60_000)
  end
end
