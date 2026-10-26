defmodule BbhWeb.EventController do
  use BbhWeb, :controller
  import BbhWeb.ControllerHelpers

  alias BbhWeb.EventPaths

  def index(conn, params) do
    current_year = Bbh.Time.now().year

    year =
      case params |> Map.get("jahr", "") |> Integer.parse() do
        {y, _} -> y
        :error -> current_year
      end

    # The year switcher spans every year with public events plus the current one, so
    # a year published ahead (next year's dates after the JHV) is reachable.
    years = Bbh.Calendar.event_years()
    {min_year, max_year} = Enum.min_max([current_year | years])

    render(conn, :index,
      page_title: "Termine #{year}",
      year: year,
      events: Bbh.Calendar.list_events_by_year(year),
      prev_disabled: year <= min_year,
      next_disabled: year >= max_year
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

  # A festival's programme item has no page of its own: its URL permanently redirects
  # to the item's anchor on the festival page (typed or shared item URLs keep working).
  def child(conn, %{"year" => year, "slug" => slug, "child" => child_slug}) do
    with y when not is_nil(y) <- parse_year(year),
         item when not is_nil(item) <- Bbh.Calendar.get_public_child(y, slug, child_slug) do
      conn
      |> put_status(:moved_permanently)
      |> redirect(to: EventPaths.path(item))
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
end
