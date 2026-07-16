defmodule BbhWeb.EventController do
  use BbhWeb, :controller
  import BbhWeb.ControllerHelpers

  def index(conn, params) do
    year =
      case params |> Map.get("jahr", "") |> Integer.parse() do
        {y, _} -> y
        :error -> Date.utc_today().year
      end

    render(conn, :index,
      page_title: "Termine #{year}",
      year: year,
      events: Bbh.Calendar.list_events_by_year(year),
      years: Bbh.Calendar.event_years()
    )
  end

  def show(conn, %{"year" => year, "slug" => slug}) do
    with y when not is_nil(y) <- parse_year(year),
         event when not is_nil(event) <- Bbh.Calendar.get_public_event(slug, y) do
      render(conn, :show, page_title: event.title, event: event)
    else
      _ -> not_found(conn)
    end
  end

  def feed(conn, _params) do
    ical = Bbh.ICal.feed(Bbh.Calendar.all_public_events(), site_url())
    send_ical(conn, ical, "termine.ics")
  end

  def ics(conn, %{"year" => year, "slug" => slug}) do
    with y when not is_nil(y) <- parse_year(year),
         event when not is_nil(event) <- Bbh.Calendar.get_public_event(slug, y) do
      send_ical(conn, Bbh.ICal.single(event, site_url()), "#{slug}.ics")
    else
      _ -> not_found(conn)
    end
  end

  defp send_ical(conn, body, filename) do
    conn
    |> put_resp_content_type("text/calendar")
    |> put_resp_header("content-disposition", ~s(inline; filename="#{filename}"))
    |> send_resp(200, body)
  end

  defp site_url, do: Application.get_env(:bbh, :site_url, "https://buterland-beckerhook.de")
end
