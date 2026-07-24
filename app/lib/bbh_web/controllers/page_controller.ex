defmodule BbhWeb.PageController do
  use BbhWeb, :controller

  def home(conn, _params) do
    render(conn, :home,
      page_title: "Startseite",
      articles: Bbh.Content.latest_articles(4),
      next_event: Bbh.Calendar.next_event(),
      thrones: Bbh.Content.current_thrones()
    )
  end
end
