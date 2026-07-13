defmodule Bbh.ICal do
  @moduledoc "Builds RFC 5545 iCalendar text for events."
  alias Bbh.Calendar.Event

  @prodid "-//Buterland-Beckerhook e.V.//Termine//DE"

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
    #{body}END:VCALENDAR\r
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
  defp dtstart(%Event{starts_at: s}), do: "DTSTART:#{stamp(s)}"

  defp dtend(%Event{ends_at: nil}), do: nil
  defp dtend(%Event{all_day: true, ends_at: e}), do: "DTEND;VALUE=DATE:#{date(e)}"
  defp dtend(%Event{ends_at: e}), do: "DTEND:#{stamp(e)}"

  defp stamp(%DateTime{} = dt) do
    dt = DateTime.truncate(dt, :second)
    "#{date(dt)}T#{pad(dt.hour)}#{pad(dt.minute)}#{pad(dt.second)}Z"
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
