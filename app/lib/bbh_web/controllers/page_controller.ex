defmodule BbhWeb.PageController do
  use BbhWeb, :controller

  alias Bbh.Calendar

  def home(conn, _params) do
    now = Bbh.Time.now()
    next_event = Calendar.next_event(now)
    # For a festival: the programme item to show (running or next) and the one the
    # countdown counts down to (the next to start — a running item has none left).
    next_child = next_event && Calendar.next_child(next_event, now)
    countdown_child = next_child && Calendar.next_child_to_start(next_event, now)

    render(conn, :home,
      page_title: "Startseite",
      settings: Bbh.Settings.get(),
      articles: Bbh.Content.latest_articles(4),
      next_event: next_event,
      next_child: next_child,
      countdown: BbhWeb.PageHTML.countdown(next_event, next_child, countdown_child, now),
      now: now,
      thrones: Bbh.Content.current_thrones()
    )
  end
end
