defmodule Bbh.ICal do
  @moduledoc "Builds RFC 5545 iCalendar text for events."
  alias Bbh.Calendar.Event

  @prodid "-//Buterland-Beckerhook e.V.//Termine//DE"

  # Static VTIMEZONE for Europe/Berlin (CET/CEST). All club events are local time;
  # emitting them with TZID + this definition lets calendar apps place them correctly
  # instead of misreading naive local times as UTC.
  @vtimezone """
  BEGIN:VTIMEZONE\r
  TZID:Europe/Berlin\r
  BEGIN:DAYLIGHT\r
  TZOFFSETFROM:+0100\r
  TZOFFSETTO:+0200\r
  TZNAME:CEST\r
  DTSTART:19700329T020000\r
  RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU\r
  END:DAYLIGHT\r
  BEGIN:STANDARD\r
  TZOFFSETFROM:+0200\r
  TZOFFSETTO:+0100\r
  TZNAME:CET\r
  DTSTART:19701025T030000\r
  RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU\r
  END:STANDARD\r
  END:VTIMEZONE\r
  """

  @doc "A full VCALENDAR feed for a list of events."
  def feed(events, site_url) do
    body = Enum.map_join(events, "", &vevent(&1, site_url))

    """
    BEGIN:VCALENDAR\r
    VERSION:2.0\r
    PRODID:#{@prodid}\r
    CALSCALE:GREGORIAN\r
    METHOD:PUBLISH\r
    X-WR-CALNAME:Buterland-Beckerhook e.V.\r
    X-PUBLISHED-TTL:P1W\r
    #{@vtimezone}#{body}END:VCALENDAR\r
    """
  end

  @doc "A single-event VCALENDAR (for download)."
  def single(%Event{} = event, site_url), do: feed([event], site_url)

  defp vevent(%Event{} = e, site_url) do
    url = "#{site_url}/termine/#{e.year}/#{e.slug}"

    lines =
      [
        "BEGIN:VEVENT",
        "UID:#{e.id}@buterland-beckerhook.de",
        "DTSTAMP:#{stamp(e.updated_at)}",
        dtstart(e),
        dtend(e),
        "SUMMARY:#{escape(e.title)}",
        e.location && "LOCATION:#{escape(location_text(e.location))}",
        e.body && "DESCRIPTION:#{escape(strip_html(e.body))}",
        e.status == "canceled" && "STATUS:CANCELLED",
        "URL:#{url}",
        "END:VEVENT"
      ]
      |> Enum.reject(&(&1 in [nil, false]))

    Enum.map_join(lines, "", &(&1 <> "\r\n"))
  end

  defp dtstart(%Event{all_day: true, starts_at: s}), do: "DTSTART;VALUE=DATE:#{date(s)}"
  defp dtstart(%Event{starts_at: s}), do: "DTSTART;TZID=Europe/Berlin:#{local_stamp(s)}"

  defp dtend(%Event{ends_at: nil}), do: nil
  defp dtend(%Event{all_day: true, ends_at: e}), do: "DTEND;VALUE=DATE:#{date(e)}"
  defp dtend(%Event{ends_at: e}), do: "DTEND;TZID=Europe/Berlin:#{local_stamp(e)}"

  # DTSTAMP is a genuine UTC timestamp → keep the Z form.
  defp stamp(%DateTime{} = dt) do
    dt = DateTime.truncate(dt, :second)
    "#{date(dt)}T#{pad(dt.hour)}#{pad(dt.minute)}#{pad(dt.second)}Z"
  end

  # Event start/end are stored as Europe/Berlin wall-clock time; emit the components
  # verbatim (no Z) alongside TZID=Europe/Berlin.
  defp local_stamp(%DateTime{} = dt) do
    dt = DateTime.truncate(dt, :second)
    "#{date(dt)}T#{pad(dt.hour)}#{pad(dt.minute)}#{pad(dt.second)}"
  end

  defp date(%DateTime{} = dt), do: "#{dt.year}#{pad(dt.month)}#{pad(dt.day)}"

  defp pad(n), do: String.pad_leading(Integer.to_string(n), 2, "0")

  defp location_text(loc) do
    [loc.name, loc.street, [loc.zip, loc.city] |> Enum.reject(&is_nil/1) |> Enum.join(" ")]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(", ")
  end

  defp strip_html(html), do: html |> String.replace(~r/<[^>]*>/, "") |> String.trim()

  # RFC 5545 text escaping.
  defp escape(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace(";", "\\;")
    |> String.replace(",", "\\,")
    |> String.replace("\n", "\\n")
  end
end
