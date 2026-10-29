defmodule BbhWeb.Admin.SiteSettingsLiveTest do
  use BbhWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_admin

  test "saves the notice text and quiet hours", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/website")

    html =
      lv
      |> form("#site-settings-form",
        site_settings: %{
          home_notice_enabled: "true",
          home_notice_text: "Wichtiger Hinweis",
          quiet_hours_enabled: "true",
          quiet_hours_start: "23",
          quiet_hours_end: "7"
        }
      )
      |> render_submit()

    assert html =~ "gespeichert"

    settings = Bbh.Settings.get()
    assert settings.home_notice_enabled
    assert settings.home_notice_text =~ "Wichtiger Hinweis"
    assert settings.quiet_hours_start == 23
    assert settings.quiet_hours_end == 7
  end

  test "the notice appears on the homepage when enabled", %{conn: conn} do
    {:ok, _} =
      Bbh.Settings.update(%{
        "home_notice_enabled" => true,
        "home_notice_text" => "Sommerfest faellt aus"
      })

    html = conn |> get(~p"/") |> html_response(200)
    assert html =~ "Sommerfest faellt aus"
  end

  test "the notice is hidden when disabled", %{conn: conn} do
    {:ok, _} =
      Bbh.Settings.update(%{
        "home_notice_enabled" => false,
        "home_notice_text" => "Versteckter Text"
      })

    html = conn |> get(~p"/") |> html_response(200)
    refute html =~ "Versteckter Text"
  end

  describe "Postfach tab" do
    test "saves the reminder settings", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/website/postfach")

      lv
      |> form("#tickets-settings-form",
        tickets: %{
          ticket_reminder_hour: "7",
          ticket_remind_unassigned_hours: "12",
          ticket_remind_idle_days: "5",
          ticket_remind_waiting_days: "10",
          ticket_escalate_days: "2",
          ticket_admin_digest_enabled: "false"
        }
      )
      |> render_submit()

      assert %{
               ticket_reminder_hour: 7,
               ticket_remind_unassigned_hours: 12,
               ticket_remind_idle_days: 5,
               ticket_remind_waiting_days: 10,
               ticket_escalate_days: 2,
               ticket_admin_digest_enabled: false
             } = Bbh.Settings.get()
    end

    test "refuses values out of range", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/website/postfach")

      html =
        lv
        |> form("#tickets-settings-form", tickets: %{ticket_remind_idle_days: "0"})
        |> render_submit()

      assert html =~ "must be greater than or equal to 1" or html =~ "größer"
      assert Bbh.Settings.get().ticket_remind_idle_days == 7
    end

    test "the tabs switch between the two forms", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/website")
      assert has_element?(lv, "#site-settings-form")
      refute has_element?(lv, "#tickets-settings-form")

      lv |> element(~s|a[href="/admin/website/postfach"]|) |> render_click()
      assert has_element?(lv, "#tickets-settings-form")
    end
  end
end
