defmodule BbhWeb.EventHTML do
  use BbhWeb, :html

  embed_templates "event_html/*"

  @months ~w(Januar Februar März April Mai Juni Juli August September Oktober November Dezember)
  @month_abbr ~w(Jan Feb Mär Apr Mai Jun Jul Aug Sep Okt Nov Dez)

  @doc "Group chronological events into `{\"Monat\", [events]}` tuples, ordered by month."
  def month_groups(events) do
    events
    |> Enum.group_by(& &1.starts_at.month)
    |> Enum.sort_by(fn {month, _} -> month end)
    |> Enum.map(fn {month, evs} -> {Enum.at(@months, month - 1), evs} end)
  end

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
      %{
        "@context" => "https://schema.org",
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
      # escape: :html_safe encodes `<`, `>`, `&` so event-supplied strings can't
      # break out of the surrounding <script> tag (e.g. a title with "</script>").
      |> Jason.encode!(escape: :html_safe)

    Phoenix.HTML.raw(~s(<script type="application/ld+json">) <> json <> "</script>")
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
