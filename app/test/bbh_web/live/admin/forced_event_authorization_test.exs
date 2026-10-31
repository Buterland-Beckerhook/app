defmodule BbhWeb.Admin.ForcedEventAuthorizationTest do
  @moduledoc """
  The admin forms hide what a role may not do, but a LiveView event can be sent by
  hand. These tests send the hidden events as an editor (strong session, so only the
  role is in the way) and check the server refuses them and nothing changes.
  """
  use BbhWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Bbh.ContentFixtures
  import Bbh.CalendarFixtures
  import Bbh.ClubFixtures

  alias Bbh.{Calendar, Club, Content}

  @denied "Keine Berechtigung zum Löschen."

  describe "an editor deleting" do
    setup :register_and_log_in_user

    # Each sends the confirmation the form asks for, so only authorization refuses.
    test "an article", %{conn: conn} do
      article = article_fixture()
      {:ok, lv, _html} = live(conn, ~p"/admin/artikel/#{article.id}/bearbeiten")

      assert render_click(lv, "delete", %{"confirm" => article.slug}) =~ @denied
      assert Content.get_article(article.id)
    end

    test "a page", %{conn: conn} do
      page = page_fixture()
      {:ok, lv, _html} = live(conn, ~p"/admin/seiten/#{page.id}/bearbeiten")

      assert render_click(lv, "delete", %{"confirm" => page.slug}) =~ @denied
      assert Content.Pages.get_page!(page.id)
    end

    test "a person", %{conn: conn} do
      person = person_fixture()
      {:ok, lv, _html} = live(conn, ~p"/admin/personen/#{person.id}/bearbeiten")

      assert render_click(lv, "delete", %{"confirm" => person.name}) =~ @denied
      assert Club.get_person!(person.id)
    end

    test "a location", %{conn: conn} do
      location = location_fixture()
      {:ok, lv, _html} = live(conn, ~p"/admin/orte/#{location.id}/bearbeiten")

      assert render_click(lv, "delete", %{"confirm" => location.key}) =~ @denied
      assert Calendar.Locations.get_location!(location.id)
    end

    test "a trophy", %{conn: conn} do
      trophy = trophy_fixture()
      {:ok, lv, _html} = live(conn, ~p"/admin/pokale/#{trophy.id}/bearbeiten")

      assert render_click(lv, "delete", %{"confirm" => trophy.name}) =~ @denied
      assert Club.get_trophy!(trophy.id)
    end

    test "a trophy win", %{conn: conn} do
      win = trophy_win_fixture()
      {:ok, lv, _html} = live(conn, ~p"/admin/pokale/sieger/#{win.id}/bearbeiten")

      assert render_click(lv, "delete", %{"confirm" => win.winner}) =~ @denied
      assert Club.get_trophy_win!(win.id)
    end

    test "a tag", %{conn: conn} do
      article = article_fixture(%{tags: ["Jugend"]})
      {:ok, lv, _html} = live(conn, ~p"/admin/schlagworte")

      assert render_click(lv, "delete", %{"tag" => "Jugend"}) =~ @denied
      assert Content.get_article(article.id).tags == ["Jugend"]
    end

    test "a public event", %{conn: conn} do
      event = event_fixture()
      {:ok, lv, _html} = live(conn, ~p"/admin/termine/#{event.id}/bearbeiten")

      assert render_click(lv, "delete", %{"confirm" => event.slug}) =~ @denied
      assert Calendar.get_event(event.id)
    end
  end

  describe "an editor saving an event" do
    setup :register_and_log_in_user

    test "into an internal calendar they were not granted", %{conn: conn} do
      [calendar | _] = Calendar.Event.calendars()
      {:ok, lv, _html} = live(conn, ~p"/admin/termine/neu")

      html =
        render_submit(lv, "save", %{
          "event" => %{
            "title" => "Vorstandssitzung",
            "calendar" => calendar,
            "starts_at" => "2030-03-01T19:00"
          }
        })

      assert html =~ "Für diesen Kalender fehlt die Berechtigung."
      refute Bbh.Repo.get_by(Calendar.Event, title: "Vorstandssitzung")
    end
  end

  describe "a Postfach user without the admin role" do
    setup %{conn: conn} do
      admin = Bbh.AccountsFixtures.admin_user_fixture()
      {:ok, user} = Bbh.Accounts.update_user_role(Bbh.AccountsFixtures.user_fixture(), "tickets")
      {:ok, _} = Bbh.Tickets.Grants.set_grants(admin, user, ["info"])
      %{conn: log_in_user(conn, user)}
    end

    test "is sent away from Auskunft & Löschung", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/admin/postfach", flash: flash}}} =
               live(conn, ~p"/admin/postfach/auskunft")

      assert flash["error"] == "Nur für Administratoren."
    end
  end
end
