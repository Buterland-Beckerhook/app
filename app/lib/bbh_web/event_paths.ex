defmodule BbhWeb.EventPaths do
  @moduledoc """
  The one place public event URLs are built — pages, pushes, iCal, search, sitemap.

    * a top-level event: `/termine/:year/:slug`;
    * a programme item: under its festival, either as an anchor on the festival page
      (`/termine/:year/:parent#:child`) or as its own page
      (`/termine/:year/:parent/:child`), depending on `config :bbh, :event_child_pages`.

  A programme item needs its `parent` loaded; the `Bbh.Calendar` queries that return
  items set it.
  """
  alias Bbh.Calendar.Event

  @doc "Site-relative path of a public event."
  def path(%Event{parent_id: nil, year: year, slug: slug}), do: "/termine/#{year}/#{slug}"

  def path(%Event{parent: %Event{} = parent, slug: slug}) do
    if child_pages?(), do: "#{path(parent)}/#{slug}", else: "#{path(parent)}##{slug}"
  end

  @doc "Absolute URL of a public event, on `base` (default: the endpoint's URL)."
  def url(%Event{} = event, base \\ BbhWeb.Endpoint.url()), do: base <> path(event)

  @doc "Whether programme items get pages of their own (otherwise: anchors)."
  def child_pages?, do: Application.get_env(:bbh, :event_child_pages, false)
end
