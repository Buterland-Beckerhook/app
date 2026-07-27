defmodule BbhWeb.Plugs.NoIndexTest do
  use BbhWeb.ConnCase

  # The whole point of the plug is that the public beta cannot be indexed even if the
  # reverse-proxy noindex middleware is ever dropped. These pin both branches: the header
  # is present exactly when the flag is on, and absent (prod default) when it is off.

  defp robots_tag(conn), do: conn |> get_resp_header("x-robots-tag") |> List.first()

  setup do
    original = Application.get_env(:bbh, :noindex, false)
    on_exit(fn -> Application.put_env(:bbh, :noindex, original) end)
  end

  test "stamps X-Robots-Tag on every response when enabled", %{conn: conn} do
    Application.put_env(:bbh, :noindex, true)

    assert conn |> get(~p"/") |> robots_tag() == "noindex, nofollow"
    # Static assets are served by Plug.Static, which the plug still covers via before_send.
    assert conn |> get(~p"/robots.txt") |> robots_tag() == "noindex, nofollow"
  end

  test "does nothing when disabled (prod default)", %{conn: conn} do
    Application.put_env(:bbh, :noindex, false)

    assert conn |> get(~p"/") |> robots_tag() == nil
  end
end
