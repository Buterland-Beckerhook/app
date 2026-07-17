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
end
