defmodule BbhWeb.ClientIpTest do
  use ExUnit.Case, async: true

  import Plug.Test, only: [conn: 2]

  alias BbhWeb.ClientIp

  @proxy {172, 18, 0, 2}

  describe "resolve/2" do
    test "takes the entry our proxy appended, not the one the client forged" do
      assert ClientIp.resolve(@proxy, ["1.2.3.4, 203.0.113.7"]) == "203.0.113.7"
    end

    test "joins repeated header lines before picking the last entry" do
      assert ClientIp.resolve(@proxy, ["1.2.3.4", "198.51.100.1, 203.0.113.7"]) ==
               "203.0.113.7"
    end

    test "ignores the header when the peer is not a trusted proxy" do
      assert ClientIp.resolve({203, 0, 113, 9}, ["1.2.3.4"]) == "203.0.113.9"
    end

    test "falls back to the peer when the header is missing or garbage" do
      assert ClientIp.resolve(@proxy, []) == "172.18.0.2"
      assert ClientIp.resolve(@proxy, ["not-an-ip"]) == "172.18.0.2"
      assert ClientIp.resolve(@proxy, ["1.2.3.4, "]) == "172.18.0.2"
    end

    test "handles IPv6 clients and proxies" do
      assert ClientIp.resolve({0, 0, 0, 0, 0, 0, 0, 1}, ["2001:db8::1"]) == "2001:db8::1"
      assert ClientIp.resolve({0xFD00, 0, 0, 0, 0, 0, 0, 2}, ["203.0.113.7"]) == "203.0.113.7"
      assert ClientIp.resolve({0x2001, 0xDB8, 0, 0, 0, 0, 0, 5}, ["1.2.3.4"]) == "2001:db8::5"
    end

    test "treats an IPv4-mapped private peer as trusted" do
      mapped = {0, 0, 0, 0, 0, 0xFFFF, 0xAC12, 0x0002}
      assert ClientIp.resolve(mapped, ["203.0.113.7"]) == "203.0.113.7"
    end

    test "is unknown without a peer" do
      assert ClientIp.resolve(nil, ["1.2.3.4"]) == "unknown"
    end
  end

  describe "trusted_proxy?/1" do
    test "private and loopback ranges only" do
      for ip <- [
            {127, 0, 0, 1},
            {10, 1, 2, 3},
            {172, 16, 0, 1},
            {172, 31, 255, 1},
            {192, 168, 1, 1}
          ] do
        assert ClientIp.trusted_proxy?(ip)
      end

      for ip <- [{172, 15, 0, 1}, {172, 32, 0, 1}, {8, 8, 8, 8}, {192, 169, 0, 1}] do
        refute ClientIp.trusted_proxy?(ip)
      end
    end
  end

  test "get/1 reads the conn" do
    conn =
      conn(:get, "/")
      |> Map.put(:remote_ip, @proxy)
      |> Plug.Conn.put_req_header("x-forwarded-for", "6.6.6.6, 203.0.113.7")

    assert ClientIp.get(conn) == "203.0.113.7"
  end
end
