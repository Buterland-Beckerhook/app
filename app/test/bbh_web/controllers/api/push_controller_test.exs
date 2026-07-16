defmodule BbhWeb.Api.PushControllerTest do
  use BbhWeb.ConnCase, async: true

  alias Bbh.Notifications
  alias Bbh.Notifications.PushSubscription
  alias Bbh.Repo

  defp json_conn(conn), do: put_req_header(conn, "content-type", "application/json")

  describe "POST /api/push/subscribe" do
    test "stores a subscription for a trusted endpoint", %{conn: conn} do
      params = %{
        "endpoint" => "https://fcm.googleapis.com/fcm/send/abc",
        "keys" => %{"p256dh" => "pk", "auth" => "ak"},
        "categories" => ["news"]
      }

      conn = conn |> json_conn() |> post(~p"/api/push/subscribe", Jason.encode!(params))

      assert json_response(conn, 200) == %{"ok" => true}
      assert Repo.get_by(PushSubscription, endpoint: params["endpoint"])
    end

    test "rejects an untrusted endpoint with 422", %{conn: conn} do
      params = %{
        "endpoint" => "https://169.254.169.254/x",
        "keys" => %{"p256dh" => "pk", "auth" => "ak"}
      }

      conn = conn |> json_conn() |> post(~p"/api/push/subscribe", Jason.encode!(params))
      assert json_response(conn, 422) == %{"ok" => false}
    end
  end

  describe "POST /api/push/unsubscribe" do
    test "removes a subscription", %{conn: conn} do
      {:ok, sub} =
        Notifications.subscribe(%{
          "endpoint" => "https://fcm.googleapis.com/fcm/send/xyz",
          "keys" => %{"p256dh" => "pk", "auth" => "ak"}
        })

      conn =
        conn
        |> json_conn()
        |> post(~p"/api/push/unsubscribe", Jason.encode!(%{"endpoint" => sub.endpoint}))

      assert json_response(conn, 200) == %{"ok" => true}
      refute Repo.get(PushSubscription, sub.id)
    end

    test "returns 400 without an endpoint", %{conn: conn} do
      conn = conn |> json_conn() |> post(~p"/api/push/unsubscribe", Jason.encode!(%{}))
      assert json_response(conn, 400) == %{"ok" => false}
    end
  end
end
