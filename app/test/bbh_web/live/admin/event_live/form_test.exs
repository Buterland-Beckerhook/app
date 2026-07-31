defmodule BbhWeb.Admin.EventLive.FormTest do
  use BbhWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Bbh.Calendar.Event
  alias Bbh.Calendar.EventReminder

  setup :register_and_log_in_admin

  test "adds a reminder row and creates the event with it", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/termine/neu")

    # Clicking "+ Erinnerung hinzufügen" appends an empty reminder row (sort_param).
    html =
      lv
      |> element("#event-form")
      |> render_change(%{"event" => %{"title" => "Sommerfest", "reminders_sort" => ["new"]}})

    assert html =~ "event[reminders][0][lead_days]"

    params = %{
      "title" => "Sommerfest",
      "slug" => "sommerfest-test",
      "status" => "published",
      "starts_at" => "2027-06-01T10:00",
      "reminders_sort" => ["0"],
      "reminders" => %{"0" => %{"lead_days" => "14", "text" => "In zwei Wochen!"}}
    }

    lv |> form("#event-form", event: params) |> render_submit()
    assert_redirect(lv, ~p"/admin/termine")

    event = Bbh.Repo.get_by!(Event, slug: "sommerfest-test")

    assert [%EventReminder{lead_days: 14, text: "In zwei Wochen!"}] =
             Bbh.Repo.all(Ecto.assoc(event, :reminders))
  end

  test "dropping all reminders (incl. the last) removes them", %{conn: conn} do
    event =
      Bbh.CalendarFixtures.event_fixture(slug: "mit-erinnerungen", starts_at: ~U[2027-06-01 10:00:00Z])

    for lead <- [7, 14], do: %EventReminder{event_id: event.id, lead_days: lead} |> Bbh.Repo.insert!()
    assert length(Bbh.Repo.all(Ecto.assoc(event, :reminders))) == 2

    {:ok, lv, html} = live(conn, ~p"/admin/termine/#{event.id}/bearbeiten")

    # The trailing empty drop input must be rendered so a form where every reminder
    # was dropped still submits a reminders_drop param (Ecto keeps them otherwise).
    assert html =~ ~s(<input type="hidden" name="event[reminders_drop][]")

    # Drop both rows in one submit — the trailing hidden reminders_drop input makes
    # the "drop the last one too" case work.
    params = %{
      "title" => event.title,
      "slug" => event.slug,
      "status" => "published",
      "starts_at" => "2027-06-01T10:00",
      "reminders_sort" => ["0", "1"],
      "reminders_drop" => ["0", "1"],
      "reminders" => %{
        "0" => %{"lead_days" => "7"},
        "1" => %{"lead_days" => "14"}
      }
    }

    lv |> form("#event-form", event: params) |> render_submit()
    assert_redirect(lv, ~p"/admin/termine")

    assert Bbh.Repo.all(Ecto.assoc(event, :reminders)) == []
  end

  test "hides public-only options when an internal calendar is selected", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/admin/termine/neu")

    # A new event defaults to public → the public-only options are shown.
    assert html =~ "Öffentlich ankündigen"
    assert html =~ "iCal-Export aktivieren"
    assert html =~ "Countdown anzeigen"
    assert html =~ "Erinnerungen"

    # Selecting an internal calendar hides all of them.
    html =
      lv
      |> element("#event-form")
      |> render_change(%{"event" => %{"title" => "Intern", "calendar" => "vorstand"}})

    refute html =~ "Öffentlich ankündigen"
    refute html =~ "iCal-Export aktivieren"
    refute html =~ "Countdown anzeigen"
    refute html =~ "Countdown ab"
    refute html =~ "Erinnerungen"

    # Toggling back to public re-shows the options.
    html =
      lv
      |> element("#event-form")
      |> render_change(%{"event" => %{"title" => "Wieder öffentlich", "calendar" => ""}})

    assert html =~ "Öffentlich ankündigen"
    assert html =~ "Erinnerungen"
  end

  test "the edit form of an existing internal event hides the public-only options",
       %{conn: conn} do
    event = Bbh.CalendarFixtures.event_fixture(calendar: "vorstand", slug: "intern-edit")

    {:ok, _lv, html} = live(conn, ~p"/admin/termine/#{event.id}/bearbeiten")

    refute html =~ "Öffentlich ankündigen"
    refute html =~ "iCal-Export aktivieren"
    refute html =~ "Countdown anzeigen"
    refute html =~ "Erinnerungen"
  end
end
