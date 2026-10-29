defmodule BbhWeb.ClientIp do
  @moduledoc """
  The one place that decides which address a request came from.

  The app sits behind a reverse proxy (Traefik in production, Caddy in dev), so the TCP
  peer is the proxy and the client is named in `X-Forwarded-For`. That header is a list
  every hop appends to — and its **left-most** entry is whatever the client chose to send.
  Only the **right-most** entry was written by our own proxy, so that is the one we take.

  The header is honoured only when the peer itself is a proxy we trust: a loopback or
  private address (the Docker networks). A client reaching the app directly gets its
  socket address, whatever header it sends.

  Rate limiting, the login log and the membership submission record all read the address
  through here, so a forged header can neither pick its own rate-limit bucket nor end up
  as evidence.
  """

  import Bitwise

  @doc "The client address of a request, as a string."
  def get(%Plug.Conn{} = conn) do
    resolve(conn.remote_ip, Plug.Conn.get_req_header(conn, "x-forwarded-for"))
  end

  @doc """
  The client address of a LiveView, from its connect info (`:peer_data`, `:x_headers`).
  `"unknown"` on the disconnected mount, which has neither.
  """
  def from_socket(socket) do
    peer =
      case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
        %{address: address} -> address
        _ -> nil
      end

    forwarded =
      for {"x-forwarded-for", value} <-
            List.wrap(Phoenix.LiveView.get_connect_info(socket, :x_headers)),
          do: value

    resolve(peer, forwarded)
  end

  @doc """
  Picks the client address from the peer address and the `X-Forwarded-For` values.
  Pure, so the rule is testable without a connection.
  """
  def resolve(nil, _forwarded), do: "unknown"

  def resolve(peer, forwarded) when is_tuple(peer) do
    with true <- trusted_proxy?(peer),
         {:ok, client} <- last_forwarded(forwarded) do
      format(client)
    else
      _ -> format(peer)
    end
  end

  # Multiple header lines are one list in order (RFC 9110 §5.3), so join before splitting.
  defp last_forwarded(values) do
    values
    |> Enum.join(",")
    |> String.split(",")
    |> List.last()
    |> case do
      nil -> :error
      entry -> entry |> String.trim() |> String.to_charlist() |> :inet.parse_address()
    end
  end

  defp format(ip), do: ip |> :inet.ntoa() |> to_string()

  @doc "Whether an address belongs to a proxy whose `X-Forwarded-For` we believe."
  def trusted_proxy?({127, _, _, _}), do: true
  def trusted_proxy?({10, _, _, _}), do: true
  def trusted_proxy?({172, b, _, _}) when b in 16..31, do: true
  def trusted_proxy?({192, 168, _, _}), do: true
  def trusted_proxy?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  # IPv4-mapped IPv6 (::ffff:a.b.c.d), as a dual-stack listener reports IPv4 peers.
  def trusted_proxy?({0, 0, 0, 0, 0, 0xFFFF, hi, lo}),
    do: trusted_proxy?({hi >>> 8, hi &&& 0xFF, lo >>> 8, lo &&& 0xFF})

  # Unique local addresses fc00::/7.
  def trusted_proxy?({a, _, _, _, _, _, _, _}) when (a &&& 0xFE00) == 0xFC00, do: true
  def trusted_proxy?(_), do: false
end
