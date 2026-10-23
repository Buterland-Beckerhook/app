defmodule Bbh.Notifications.DeviceTest do
  use ExUnit.Case, async: true

  alias Bbh.Notifications.Device

  doctest Device

  @user_agents [
    {"Mozilla/5.0 (Windows NT 10.0) Chrome/130.0 Safari/537.36 Edg/130.0", "Edge · Windows"},
    {"Mozilla/5.0 (Linux; Android 14; K) Chrome/130.0 Mobile Safari/537.36", "Chrome · Android"},
    {"Mozilla/5.0 (Linux; Android 14) SamsungBrowser/26.0 Chrome/122.0 Mobile Safari/537.36",
     "Samsung Internet · Android"},
    {"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Version/18.1 Safari/605.1.15",
     "Safari · macOS"},
    {"Mozilla/5.0 (X11; Linux x86_64; rv:131.0) Gecko/20100101 Firefox/131.0", "Firefox · Linux"},
    {"Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) Version/18.1 Safari/604.1",
     "Safari · iOS"}
  ]

  test "describes common browsers" do
    for {ua, expected} <- @user_agents do
      assert Device.describe(ua) == expected, ua
    end
  end

  test "unrecognised or missing User-Agents describe nothing (no raw header stored)" do
    assert Device.describe("SomethingElse/1.0") == nil
    assert Device.describe("") == nil
  end
end
