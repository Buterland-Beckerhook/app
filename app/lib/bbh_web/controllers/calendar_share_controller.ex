defmodule BbhWeb.CalendarShareController do
  use BbhWeb, :controller
  import BbhWeb.ControllerHelpers

  @doc "Serve the shared internal calendar as a read-only iCal feed, or 404."
  def feed(conn, %{"token" => token}) do
    case Bbh.Calendar.Shares.verify_share_token(token) do
      {:ok, share} ->
        # `private`: the URL is the credential, so no shared cache may keep the body.
        feed = Bbh.Calendar.Feeds.shared(share.calendar, site_url())
        send_ical_feed(conn, feed, "#{share.calendar}.ics", "private, max-age=3600")

      :error ->
        not_found(conn)
    end
  end
end
