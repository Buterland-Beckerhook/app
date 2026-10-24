defmodule BbhWeb.EventPaths do
  @moduledoc """
  The one place public event URLs are built — pages, pushes, iCal, search, sitemap.

    * a top-level event: `/termine/:year/:slug`;
    * a programme item: an anchor on its festival's page (`/termine/:year/:parent#:child`)
      — items have no pages of their own.

  A programme item needs its `parent` loaded; the `Bbh.Calendar` queries that return
  items set it.
  """
  alias Bbh.Calendar.Event

  @doc "Site-relative path of a public event."
  def path(%Event{parent_id: nil, year: year, slug: slug}), do: "/termine/#{year}/#{slug}"

  def path(%Event{parent: %Event{} = parent, slug: slug}), do: "#{path(parent)}##{slug}"

  @doc "Absolute URL of a public event, on `base` (default: the endpoint's URL)."
  def url(%Event{} = event, base \\ BbhWeb.Endpoint.url()), do: base <> path(event)
end
