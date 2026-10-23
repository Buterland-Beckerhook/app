defmodule BbhWeb.Admin.PushLiveTest do
  use BbhWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Bbh.NotificationsFixtures

  alias Bbh.Notifications.PushSubscription
  alias Bbh.Repo

  setup :register_and_log_in_admin

  test "lists subscriptions by their push-service host", %{conn: conn} do
    push_subscription_fixture()
    {:ok, _lv, html} = live(conn, ~p"/admin/push")

    assert html =~ "fcm.googleapis.com"
    assert html =~ "Abonnements"
  end

  test "shows the device name and description", %{conn: conn} do
    sub = push_subscription_fixture()

    sub
    |> Ecto.Changeset.change(label: "Roberts iPhone", device: "Safari · iOS")
    |> Repo.update!()

    {:ok, _lv, html} = live(conn, ~p"/admin/push")

    assert html =~ "Roberts iPhone"
    assert html =~ "Safari · iOS"
  end

  test "marks the browser viewing the page as this device", %{conn: conn} do
    mine = push_subscription_fixture()
    _other = push_subscription_fixture()
    {:ok, lv, html} = live(conn, ~p"/admin/push")
    refute html =~ "Dieses Gerät"

    html =
      lv
      |> element("#push-this-device")
      |> render_hook("this_device", %{"endpoint" => mine.endpoint})

    assert html =~ "Dieses Gerät"
    # The secret endpoint itself is never rendered.
    refute html =~ mine.endpoint
  end

  test "an unknown endpoint marks nothing", %{conn: conn} do
    push_subscription_fixture()
    {:ok, lv, _html} = live(conn, ~p"/admin/push")

    html =
      lv
      |> element("#push-this-device")
      |> render_hook("this_device", %{"endpoint" => "https://fcm.googleapis.com/x"})

    refute html =~ "Dieses Gerät"
  end

  test "deletes a subscription", %{conn: conn} do
    sub = push_subscription_fixture()
    {:ok, lv, _html} = live(conn, ~p"/admin/push")

    render_click(lv, "delete", %{"id" => sub.id})

    refute Repo.get(PushSubscription, sub.id)
  end

  test "sending an ad-hoc push confirms it was queued", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/push")

    html =
      lv
      |> form("#push-send-form",
        push: %{category: "termine", title: "Hallo", body: "Welt", url: ""}
      )
      |> render_submit()

    assert html =~ "wird gesendet"
  end

  test "can target test devices only", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/admin/push")
    assert html =~ "Nur Testgeräte"

    html =
      lv
      |> form("#push-send-form",
        push: %{category: "tester", title: "Test", body: "Probe", url: ""}
      )
      |> render_submit()

    assert html =~ "wird gesendet"
  end

  test "rejects an empty title or body", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/push")

    html =
      lv
      |> form("#push-send-form", push: %{category: "termine", title: "", body: "Welt", url: ""})
      |> render_submit()

    assert html =~ "dürfen nicht leer sein"
  end
end
