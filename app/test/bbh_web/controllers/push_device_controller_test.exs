defmodule BbhWeb.PushDeviceControllerTest do
  use BbhWeb.ConnCase, async: true

  import Bbh.AccountsFixtures
  import Bbh.TicketsFixtures

  alias Bbh.Notifications

  @body %{
    endpoint: "https://fcm.googleapis.com/fcm/send/device",
    keys: %{p256dh: "pk", auth: "ak"}
  }

  defp post_device(conn, body \\ @body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json")
    |> put_req_header("user-agent", "Mozilla/5.0 (Windows NT 10.0) Firefox/140.0")
    |> post(~p"/push/postfach", Jason.encode!(body))
  end

  test "links the browser to a Postfach user with a strong session", %{conn: conn} do
    user = user_fixture()
    granted_scope(user, ["info"])

    assert %{"ok" => true} =
             conn
             |> log_in_user(user, auth_method: "passkey")
             |> post_device()
             |> json_response(200)

    assert [device] = Notifications.list_user_devices(user)
    assert device.device =~ "Firefox"
  end

  test "refuses an untrusted endpoint", %{conn: conn} do
    user = user_fixture()
    granted_scope(user, ["info"])

    assert conn
           |> log_in_user(user, auth_method: "passkey")
           |> post_device(%{@body | endpoint: "https://evil.example.com/x"})
           |> json_response(422)
  end

  test "refuses a session without a second factor", %{conn: conn} do
    user = user_fixture()
    granted_scope(user, ["info"])

    assert conn
           |> log_in_user(user, auth_method: "magic_link")
           |> post_device()
           |> json_response(403)

    assert Notifications.list_user_devices(user) == []
  end

  test "refuses a user without Postfach access, and anonymous visitors", %{conn: conn} do
    assert conn
           |> log_in_user(user_fixture(), auth_method: "passkey")
           |> post_device()
           |> json_response(403)

    assert conn |> post_device() |> json_response(403)
  end
end
