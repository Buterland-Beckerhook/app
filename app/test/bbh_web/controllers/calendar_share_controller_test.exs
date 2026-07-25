defmodule BbhWeb.CalendarShareControllerTest do
  use BbhWeb.ConnCase, async: true

  alias Bbh.Calendar

  import Bbh.CalendarFixtures

  defp share_for(calendar, attrs \\ %{}) do
    share_with_token(Map.put(Map.new(attrs), :calendar, calendar))
  end

  defp at(offset_days) do
    DateTime.utc_now() |> DateTime.add(offset_days, :day) |> DateTime.truncate(:second)
  end

  describe "GET /kalender/geteilt/:token" do
    test "serves a text/calendar feed for a valid token", %{conn: conn} do
      event_fixture(calendar: "vorstand", status: "published", title: "Vorstandssitzung")
      {plaintext, _share} = share_for("vorstand")

      conn = get(conn, ~p"/kalender/geteilt/#{plaintext}")

      assert get_resp_header(conn, "content-type") |> hd() =~ "text/calendar"
      body = response(conn, 200)
      assert body =~ "BEGIN:VCALENDAR"
      assert body =~ "Vorstandssitzung"
      # Internal events have no public page, so no (404-bound) URL: line.
      refute body =~ "URL:"
    end

    test "is reachable without authentication", %{conn: conn} do
      {plaintext, _share} = share_for("vorstand")
      # No login setup; a 200 proves the route is public.
      assert conn |> get(~p"/kalender/geteilt/#{plaintext}") |> response(200)
    end

    test "shows only the shared calendar's events, not other calendars or public", %{conn: conn} do
      event_fixture(calendar: "vorstand", status: "published", title: "NurVorstand")
      event_fixture(calendar: "offiziere", status: "published", title: "NichtOffiziere")
      event_fixture(status: "published", title: "NichtOeffentlich")
      {plaintext, _share} = share_for("vorstand")

      body = conn |> get(~p"/kalender/geteilt/#{plaintext}") |> response(200)

      assert body =~ "NurVorstand"
      refute body =~ "NichtOffiziere"
      refute body =~ "NichtOeffentlich"
    end

    test "returns 404 for a revoked token", %{conn: conn} do
      {plaintext, share} = share_for("vorstand")
      {:ok, _} = Calendar.revoke_share(share.id)

      assert conn |> get(~p"/kalender/geteilt/#{plaintext}") |> response(404)
    end

    test "returns 404 for an expired token", %{conn: conn} do
      {plaintext, _share} = share_for("vorstand", %{expires_at: at(-1)})

      assert conn |> get(~p"/kalender/geteilt/#{plaintext}") |> response(404)
    end

    test "returns 404 for an unknown token", %{conn: conn} do
      assert conn |> get(~p"/kalender/geteilt/doesnotexist") |> response(404)
    end
  end
end
