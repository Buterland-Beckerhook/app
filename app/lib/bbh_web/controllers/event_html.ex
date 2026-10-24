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

  @doc """
  A festival's programme as a timeline, grouped by day: past items dimmed, the running
  one highlighted, canceled ones marked. Shared by the festival page and the event
  content block (`BbhWeb.SiteComponents.block/1`). `festival.children` are its visible
  items, chronological, each with `location` loaded.

  `anchors` gives every item its slug as `id` — the festival page is where an item's
  URL points (`BbhWeb.EventPaths`), so only it may claim them.
  """
  attr :festival, :map, required: true
  attr :anchors, :boolean, default: true
  attr :day_tag, :string, default: "h3"

  def programme(assigns) do
    ~H"""
    <div :for={{day, items} <- day_groups(@festival.children)} class="mt-6">
      <.dynamic_tag tag_name={@day_tag} class="border-b border-base-300 pb-2 text-lg font-bold">
        {day}
      </.dynamic_tag>
      <ol>
        <li
          :for={item <- items}
          id={@anchors && item.slug}
          class={[
            "grid scroll-mt-24 grid-cols-[7.5rem_1fr] gap-x-4 border-b border-base-300/60 py-3 last:border-b-0 sm:grid-cols-[8.5rem_1fr_auto]",
            item_state(item) == :past && "opacity-55",
            item_state(item) == :running &&
              "-mx-3 rounded-xl border-b-0 bg-primary/8 px-3 ring-1 ring-primary/30"
          ]}
        >
          <div class="pt-0.5 text-sm font-semibold text-primary tabular-nums">
            {item_time(item)}
          </div>
          <div class="min-w-0">
            <div class="flex flex-wrap items-center gap-2">
              <span class="font-semibold">{item.title}</span>
              <span
                :if={item_state(item) == :running}
                class="rounded bg-primary px-2 py-0.5 text-xs font-bold text-primary-content uppercase"
              >
                Jetzt
              </span>
              <span
                :if={item.status == "canceled"}
                class="rounded bg-error/10 px-2 py-0.5 text-xs font-medium text-error"
              >
                Abgesagt
              </span>
            </div>
            <p :if={item.status == "canceled" && item.cancel_reason} class="text-sm text-error">
              {item.cancel_reason}
            </p>
            <p :if={loc = item_location(item, @festival)} class="text-sm text-muted sm:hidden">
              {loc.name}
            </p>
            <details :if={item.body} class="group mt-1 text-sm">
              <summary class="cursor-pointer text-primary hover:underline">
                Mehr erfahren
              </summary>
              <div class="prose prose-sm mt-2 max-w-none dark:prose-invert">
                {render_richtext(item.body)}
              </div>
            </details>
          </div>
          <div
            :if={loc = item_location(item, @festival)}
            class="hidden pt-0.5 text-right text-sm text-muted sm:block"
          >
            {loc.name}
          </div>
        </li>
      </ol>
    </div>
    """
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
