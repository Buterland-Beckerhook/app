defmodule BbhWeb.PageController do
  use BbhWeb, :controller

  alias Bbh.Calendar

  def home(conn, _params) do
    now = Bbh.Time.now()
    next_event = Calendar.next_event(now)
    # For a festival: its first item (no programme without one), the item to show
    # (running or next) and the one the countdown counts down to once it is under way.
    first_child = next_event && Calendar.first_child(next_event)
    next_child = first_child && Calendar.next_child(next_event, now)
    countdown_child = first_child && Calendar.next_child_to_start(next_event, now)

    render(conn, :home,
      page_title: "Startseite",
      settings: Bbh.Settings.get(),
      articles: Bbh.Content.latest_articles(4),
      next_event: next_event,
      next_child: next_child && BbhWeb.PageHTML.next_child_shown?(next_child, now) && next_child,
      countdown: BbhWeb.PageHTML.countdown(next_event, first_child, countdown_child, now),
      now: now,
      thrones: Bbh.Content.current_thrones()
    )
  end
end
