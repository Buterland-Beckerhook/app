defmodule BbhWeb.Admin.TicketNotificationsLiveTest do
  use BbhWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Bbh.AccountsFixtures
  import Bbh.TicketsFixtures

  alias Bbh.Notifications
  alias Bbh.Repo

  @path "/admin/postfach/benachrichtigungen"
  @device %{
    "endpoint" => "https://fcm.googleapis.com/fcm/send/mine",
    "keys" => %{"p256dh" => "pk", "auth" => "ak"}
  }

  setup %{conn: conn} do
    user = user_fixture()
    granted_scope(user, ["info"])
    %{user: user, conn: log_in_user(conn, user, auth_method: "passkey")}
  end

  test "saves interval and channel", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, @path)

    lv
    |> form("#notification-form",
      user: %{ticket_notify_interval_minutes: "240", ticket_notify_channel: "push"}
    )
    |> render_submit()

    assert %{ticket_notify_interval_minutes: 240, ticket_notify_channel: "push"} =
             Repo.reload!(user)

    assert has_element?(lv, "#no-devices")
  end

  test "shows the site's quiet hours", %{conn: conn} do
    {:ok, _} =
      Bbh.Settings.update(%{
        quiet_hours_enabled: true,
        quiet_hours_start: 21,
        quiet_hours_end: 7
      })

    {:ok, _lv, html} = live(conn, @path)
    assert html =~ "Zwischen 21:00 und 7:00 Uhr"
    assert html =~ "Alle 4 Stunden (7, 11, 15, 19 Uhr)"
  end

  test "lists the user's devices, marks this one, removes one", %{conn: conn, user: user} do
    {:ok, mine} = Notifications.link_device(user, @device)
    {:ok, lv, _html} = live(conn, @path)
    assert has_element?(lv, "#device-#{mine.id}")
    refute has_element?(lv, "#device-#{mine.id} .badge")

    render_hook(lv, "browser_state", %{"kind" => "off", "endpoint" => mine.endpoint})
    assert has_element?(lv, "#device-#{mine.id} .badge")
    refute has_element?(lv, "#link-device")

    lv |> element("#device-#{mine.id} button") |> render_click()
    refute has_element?(lv, "#device-#{mine.id}")
    assert has_element?(lv, "#link-device")
  end

  test "does not show or remove someone else's device", %{conn: conn} do
    {:ok, theirs} = Notifications.link_device(user_fixture(), @device)
    {:ok, lv, _html} = live(conn, @path)
    refute has_element?(lv, "#device-#{theirs.id}")

    render_click(lv, "unlink", %{"id" => theirs.id})
    assert Repo.reload!(theirs).user_id
  end

  test "needs a strong session", %{user: user} do
    conn = log_in_user(build_conn(), user, auth_method: "magic_link")
    assert {:error, {:redirect, _}} = live(conn, @path)
  end
end
