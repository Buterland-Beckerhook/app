defmodule BbhWeb.CalendarShareController do
  use BbhWeb, :controller
  import BbhWeb.ControllerHelpers

  @doc "Serve the shared internal calendar as a read-only iCal feed, or 404."
  def feed(conn, %{"token" => token}) do
    case Bbh.Calendar.verify_share_token(token) do
      {:ok, share} ->
        events = Bbh.Calendar.shared_calendar_events(share.calendar)
        send_ical(conn, Bbh.ICal.feed(events, site_url()), "#{share.calendar}.ics")

      :error ->
        not_found(conn)
    end
  end
end
