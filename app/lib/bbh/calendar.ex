defmodule Bbh.Calendar do
  @moduledoc "Read/query API for events and locations."
  import Ecto.Query
  alias Bbh.Repo
  alias Bbh.Calendar.Event

  @doc "The next upcoming public event (published, announced, no internal calendar)."
  def next_event(now \\ DateTime.utc_now()) do
    Repo.one(
      from e in public_events(),
        where: e.starts_at >= ^now,
        order_by: [asc: e.starts_at],
        limit: 1,
        preload: [:location]
    )
  end

  @doc "All public events for a given year, chronological."
  def list_events_by_year(year) do
    Repo.all(
      from e in public_events(),
        where: e.year == ^year,
        order_by: [asc: e.starts_at],
        preload: [:location]
    )
  end

  @doc "A single public event by slug + year, with location and sub-events."
  def get_public_event(slug, year) do
    Repo.one(
      from e in public_events(),
        where: e.slug == ^slug and e.year == ^year,
        preload: [:location, children: ^from(c in Event, order_by: c.starts_at)]
    )
  end

  @doc "All public events (for the iCal feed)."
  def all_public_events do
    Repo.all(from e in public_events(), order_by: [asc: e.starts_at], preload: [:location])
  end

  @doc "Distinct years that have public events (for the year navigation)."
  def event_years do
    Repo.all(from e in public_events(), distinct: true, select: e.year, order_by: [desc: e.year])
  end

  # Public = published, publicly announced, not on an internal calendar.
  defp public_events do
    from e in Event, where: e.status == "published" and e.announce == true and is_nil(e.calendar)
  end
end
