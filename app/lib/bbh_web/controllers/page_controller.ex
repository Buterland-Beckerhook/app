defmodule BbhWeb.PageController do
  use BbhWeb, :controller

  def home(conn, _params) do
    render(conn, :home,
      page_title: "Startseite",
      articles: Bbh.Content.latest_articles(3),
      next_event: Bbh.Calendar.next_event(),
      throne: Bbh.Content.current_throne()
    )
  end
end
