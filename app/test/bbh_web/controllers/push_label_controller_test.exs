defmodule BbhWeb.PushLabelControllerTest do
  use BbhWeb.ConnCase, async: true

  alias Bbh.Notifications

  @push_endpoint "https://fcm.googleapis.com/fcm/send/label"

  setup do
    {:ok, _} =
      Notifications.subscribe(%{
        "endpoint" => @push_endpoint,
        "keys" => %{"p256dh" => "pk", "auth" => "ak"}
      })

    :ok
  end

  defp post_label(conn, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json")
    |> post(~p"/push/label", Jason.encode!(body))
  end

  describe "as admin" do
    setup :register_and_log_in_admin

    test "names the device and clears the name", %{conn: conn} do
      body = %{endpoint: @push_endpoint, label: "Roberts iPhone"}
      assert %{"label" => "Roberts iPhone"} = conn |> post_label(body) |> json_response(200)

      assert {:ok, %{label: "Roberts iPhone"}} = Notifications.subscription_status(@push_endpoint)

      assert %{"label" => nil} =
               conn |> post_label(%{endpoint: @push_endpoint, label: ""}) |> json_response(200)
    end

    test "404 unknown endpoint, 422 too long, 400 malformed", %{conn: conn} do
      assert conn
             |> post_label(%{endpoint: "https://fcm.googleapis.com/x", label: "A"})
             |> json_response(404)

      assert conn
             |> post_label(%{endpoint: @push_endpoint, label: String.duplicate("x", 41)})
             |> json_response(422)

      assert conn |> post_label(%{endpoint: @push_endpoint, label: 1}) |> json_response(400)
    end
  end

  describe "as admin with a plain magic-link session" do
    setup :register_and_log_in_admin

    @tag auth_method: "magic_link"
    test "is forbidden", %{conn: conn} do
      assert conn |> post_label(%{endpoint: @push_endpoint, label: "X"}) |> json_response(403)
      assert {:ok, %{label: nil}} = Notifications.subscription_status(@push_endpoint)
    end
  end

  describe "as editor" do
    setup :register_and_log_in_user

    test "is forbidden", %{conn: conn} do
      assert conn |> post_label(%{endpoint: @push_endpoint, label: "X"}) |> json_response(403)
      assert {:ok, %{label: nil}} = Notifications.subscription_status(@push_endpoint)
    end
  end

  test "is forbidden when logged out", %{conn: conn} do
    assert conn |> post_label(%{endpoint: @push_endpoint, label: "X"}) |> json_response(403)
  end
end
