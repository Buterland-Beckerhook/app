defmodule BbhWeb.EventHTML do
  use BbhWeb, :html

  embed_templates "event_html/*"

  @doc "Schema.org Event JSON-LD `<script>` (raw, safe) for search engines."
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
      |> Jason.encode!()

    Phoenix.HTML.raw(~s(<script type="application/ld+json">) <> json <> "</script>")
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
