defmodule BbhWeb.PushTesterControllerTest do
  use BbhWeb.ConnCase, async: true

  alias Bbh.Notifications

  @push_endpoint "https://fcm.googleapis.com/fcm/send/tester"

  setup do
    {:ok, _} =
      Notifications.subscribe(%{
        "endpoint" => @push_endpoint,
        "keys" => %{"p256dh" => "pk", "auth" => "ak"}
      })

    :ok
  end

  defp post_tester(conn, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json")
    |> post(~p"/push/tester", Jason.encode!(body))
  end

  describe "as admin" do
    setup :register_and_log_in_admin

    test "flags and unflags the device", %{conn: conn} do
      assert conn |> post_tester(%{endpoint: @push_endpoint, tester: true}) |> json_response(200)
      assert {:ok, %{tester: true}} = Notifications.subscription_status(@push_endpoint)

      assert conn |> post_tester(%{endpoint: @push_endpoint, tester: false}) |> json_response(200)
      assert {:ok, %{tester: false}} = Notifications.subscription_status(@push_endpoint)
    end

    test "404 for an unknown endpoint, 400 for a malformed body", %{conn: conn} do
      assert conn
             |> post_tester(%{endpoint: "https://fcm.googleapis.com/x", tester: true})
             |> json_response(404)

      assert conn |> post_tester(%{endpoint: @push_endpoint, tester: "yes"}) |> json_response(400)
    end
  end

  describe "as editor" do
    setup :register_and_log_in_user

    test "is forbidden", %{conn: conn} do
      assert conn |> post_tester(%{endpoint: @push_endpoint, tester: true}) |> json_response(403)
      assert {:ok, %{tester: false}} = Notifications.subscription_status(@push_endpoint)
    end
  end

  test "is forbidden when logged out", %{conn: conn} do
    assert conn |> post_tester(%{endpoint: @push_endpoint, tester: true}) |> json_response(403)
  end
end
