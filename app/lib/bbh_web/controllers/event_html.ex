defmodule BbhWeb.EventHTML do
  use BbhWeb, :html

  embed_templates "event_html/*"

  @months ~w(Januar Februar März April Mai Juni Juli August September Oktober November Dezember)
  @month_abbr ~w(Jan Feb Mär Apr Mai Jun Jul Aug Sep Okt Nov Dez)
  @weekdays ~w(Montag Dienstag Mittwoch Donnerstag Freitag Samstag Sonntag)

  @doc "Group chronological events into `{\"Monat\", [events]}` tuples, ordered by month."
  def month_groups(events) do
    events
    |> Enum.group_by(& &1.starts_at.month)
    |> Enum.sort_by(fn {month, _} -> month end)
    |> Enum.map(fn {month, evs} -> {Enum.at(@months, month - 1), evs} end)
  end

  @doc """
  Group a festival's chronological programme by day: `[{"Samstag, 18. Juli", items}]`.
  An item belongs to the day it starts on, even when it runs past midnight.
  """
  def day_groups(items) do
    items
    |> Enum.chunk_by(&DateTime.to_date(&1.starts_at))
    |> Enum.map(fn [first | _] = day -> {day_label(first.starts_at), day} end)
  end

  defp day_label(%DateTime{} = dt) do
    "#{Enum.at(@weekdays, Date.day_of_week(dt) - 1)}, #{dt.day}. #{Enum.at(@months, dt.month - 1)}"
  end

  @doc ~s("1 Programmpunkt" / "14 Programmpunkte".)
  def programme_count(1), do: "1 Programmpunkt"
  def programme_count(n), do: "#{n} Programmpunkte"

  @doc ~s(A programme item's time span, e.g. "20:00 – 02:00 Uhr".)
  def item_time(%{starts_at: s, ends_at: %DateTime{} = e}), do: "#{hm(s)} – #{hm(e)} Uhr"
  def item_time(%{starts_at: s}), do: "#{hm(s)} Uhr"

  @doc ~s(A programme item's day and span, e.g. "So., 09:30 – 10:30 Uhr".)
  def item_when(item), do: "#{BbhWeb.Format.de_weekday_abbr(item.starts_at)}, #{item_time(item)}"

  @doc "Where a programme item is at `now`: `:past`, `:running` or `:upcoming`."
  def item_state(item, now \\ Bbh.Time.now()) do
    cond do
      past_event?(item, now) -> :past
      DateTime.compare(item.starts_at, now) != :gt -> :running
      true -> :upcoming
    end
  end

  @doc "An item's location, when it differs from the festival's (else it goes without saying)."
  def item_location(%{location: %{} = loc, location_id: id}, %{location_id: festival_location}),
    do: if(id != festival_location, do: loc)

  def item_location(_item, _festival), do: nil

  defp hm(%DateTime{} = dt), do: "#{two(dt.hour)}:#{two(dt.minute)}"

  @doc "Three-letter German month abbreviation for the date badge, e.g. \"Jul\"."
  def month_abbr(%{month: month}), do: Enum.at(@month_abbr, month - 1)

  @doc "Just the time of an event for the row's right column (or \"Ganztägig\")."
  def event_time(%{all_day: true}), do: "Ganztägig"

  def event_time(%{starts_at: %DateTime{} = dt}),
    do: "#{two(dt.hour)}:#{two(dt.minute)} Uhr"

  @doc "Has the event already passed? Dimmed rows in the list."
  def past_event?(event, now \\ Bbh.Time.now()) do
    DateTime.compare(event.ends_at || event.starts_at, now) == :lt
  end

  defp two(n), do: String.pad_leading(Integer.to_string(n), 2, "0")

  @doc "Schema.org Event JSON-LD `<script>` (raw, safe) for search engines."
  # sobelow_skip ["XSS.Raw"]
  def event_jsonld(event) do
    json =
      event
      |> jsonld_event()
      |> Map.put("@context", "https://schema.org")
      |> maybe_put("subEvent", programme_jsonld(event))
      # escape: :html_safe encodes `<`, `>`, `&` so event-supplied strings can't
      # break out of the surrounding <script> tag (e.g. a title with "</script>").
      |> Jason.encode!(escape: :html_safe)

    Phoenix.HTML.raw(~s(<script type="application/ld+json">) <> json <> "</script>")
  end

  defp jsonld_event(event) do
    %{
      "@type" => "Event",
      "name" => event.title,
      "startDate" => DateTime.to_iso8601(event.starts_at),
      "eventStatus" =>
        if(event.status == "canceled",
          do: "https://schema.org/EventCancelled",
          else: "https://schema.org/EventScheduled"
        )
    }
    |> maybe_put("endDate", event.ends_at && DateTime.to_iso8601(event.ends_at))
    |> maybe_put(
      "location",
      event.location && %{"@type" => "Place", "name" => event.location.name}
    )
  end

  defp programme_jsonld(%{children: [_ | _] = items}), do: Enum.map(items, &jsonld_event/1)
  defp programme_jsonld(_event), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
