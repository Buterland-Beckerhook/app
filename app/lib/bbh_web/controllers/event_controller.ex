defmodule BbhWeb.EventController do
  use BbhWeb, :controller
  import BbhWeb.ControllerHelpers

  alias BbhWeb.EventPaths

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

  # A festival's programme item. With item pages (EventPaths.child_pages?/0) it gets
  # its own page with previous/next links; otherwise this permanently redirects to the
  # item's anchor on the festival page, so a shared item URL keeps working either way.
  def child(conn, %{"year" => year, "slug" => slug, "child" => child_slug}) do
    with y when not is_nil(y) <- parse_year(year),
         festival when not is_nil(festival) <- Bbh.Calendar.get_public_event(slug, y),
         {prev, item, next} <- locate(festival.children, child_slug) do
      if EventPaths.child_pages?() do
        render(conn, :child,
          page_title: "#{item.title} · #{festival.title}",
          event: item,
          festival: festival,
          prev: prev,
          next: next
        )
      else
        conn
        |> put_status(:moved_permanently)
        |> redirect(to: EventPaths.path(item))
      end
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

  # Only items with pages of their own have a download; anchors share the festival's.
  def child_ics(conn, %{"year" => year, "slug" => slug, "child" => child_slug}) do
    with true <- EventPaths.child_pages?(),
         y when not is_nil(y) <- parse_year(year),
         item when not is_nil(item) <- Bbh.Calendar.get_public_child(y, slug, child_slug) do
      send_ical(conn, Bbh.ICal.single(item, site_url()), "#{child_slug}.ics")
    else
      _ -> not_found(conn)
    end
  end

  # {previous, item, next} for the item with `slug` in the chronological programme.
  defp locate(items, slug) do
    case Enum.find_index(items, &(&1.slug == slug)) do
      nil -> nil
      0 -> {nil, Enum.at(items, 0), Enum.at(items, 1)}
      i -> {Enum.at(items, i - 1), Enum.at(items, i), Enum.at(items, i + 1)}
    end
  end
end
