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
end
