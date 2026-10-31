defmodule Bbh.Calendar.Feeds do
  @moduledoc """
  The iCal subscription feeds — the public one and one per shared internal calendar —
  served from a `:persistent_term` cache of the rendered text.

  Calendar apps poll these on a timer, and the public archive only grows, so building
  a feed per request (every event with its body, then the whole text) scales with
  subscribers × history. A feed is rebuilt only when `version/0` — count and latest
  change of events and locations, one cheap aggregate — has moved. `updated_at` has
  second precision, so two saves within one second could leave the version unchanged:
  `@max_age_ms` bounds how long such a miss can serve the older text.

  The ETag is a hash of the text itself, so a `304 Not Modified` is never wrong.
  """
  import Ecto.Query
  alias Bbh.Repo
  alias Bbh.Calendar.{Event, Location}

  @max_age_ms :timer.minutes(5)

  @doc "`{etag, body}` of the public feed."
  def public(site_url),
    do: fetch(:public, fn -> Bbh.ICal.feed(Bbh.Calendar.all_public_events(), site_url) end)

  @doc "`{etag, body}` of the feed of one shared internal calendar."
  def shared(calendar, site_url) do
    fetch({:shared, calendar}, fn ->
      Bbh.ICal.feed(Bbh.Calendar.Shares.shared_calendar_events(calendar), site_url)
    end)
  end

  defp fetch(key, build) do
    if cache?() do
      version = version()
      now = System.monotonic_time(:millisecond)

      case :persistent_term.get({__MODULE__, key}, nil) do
        {^version, built_at, etag, body} when now - built_at < @max_age_ms ->
          {etag, body}

        _ ->
          {etag, body} = render(build)
          # A put triggers a global GC scan; at most once per feed and change (or per
          # @max_age_ms), which is far below the polling rate it saves.
          :persistent_term.put({__MODULE__, key}, {version, now, etag, body})
          {etag, body}
      end
    else
      render(build)
    end
  end

  defp render(build) do
    body = build.()
    hash = :crypto.hash(:sha256, body) |> binary_part(0, 16)
    {~s("#{Base.url_encode64(hash, padding: false)}"), body}
  end

  defp version do
    {Repo.one(from(e in Event, select: {count(e.id), max(e.updated_at)})),
     Repo.one(from(l in Location, select: {count(l.id), max(l.updated_at)}))}
  end

  defp cache?, do: Application.get_env(:bbh, __MODULE__, [])[:cache] != false
end
