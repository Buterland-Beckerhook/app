defmodule BbhWeb.Admin.BuildInfoLiveTest do
  # Not async: the build info is application env.
  use BbhWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup :register_and_log_in_admin

  setup do
    prev = Application.get_env(:bbh, :build_info)
    on_exit(fn -> Application.put_env(:bbh, :build_info, prev) end)
  end

  test "shows the running build in the sidebar and on the dashboard", %{conn: conn} do
    Application.put_env(:bbh, :build_info,
      version: "1.2.0-3-gabcdef1",
      commit: "abcdef1234567890abcdef1234567890abcdef12",
      ref: "main",
      build_tag: "20261118-1015-abcdef1",
      built_at: "2026-11-18T10:15:00Z",
      image: "ghcr.io/buterland-beckerhook/app:beta"
    )

    {:ok, lv, _html} = live(conn, ~p"/admin")

    assert lv |> element("#build-line") |> render() =~ "v1.2.0-3-gabcdef1"
    assert lv |> element("#build-image") |> render() =~ "ghcr.io/buterland-beckerhook/app:beta"
    assert lv |> element("#build-tag") |> render() =~ "20261118-1015-abcdef1"
    commit_link = ~s(#build-commit a[href$="/commit/abcdef1234567890abcdef1234567890abcdef12"])
    assert has_element?(lv, commit_link)
    assert lv |> element("#build-time") |> render() =~ "18.11.2026 11:15"
  end

  test "says so in a dev checkout", %{conn: conn} do
    Application.put_env(:bbh, :build_info, [])

    {:ok, lv, _html} = live(conn, ~p"/admin")

    assert lv |> element("#build-line") |> render() =~ "Entwicklung"
    assert has_element?(lv, "#build-info")
    refute has_element?(lv, "#build-commit")
  end
end
