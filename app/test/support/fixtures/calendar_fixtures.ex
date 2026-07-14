defmodule Bbh.CalendarFixtures do
  @moduledoc "Test helpers for creating events and locations."

  alias Bbh.Calendar

  def location_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        key: "ort-#{System.unique_integer([:positive])}",
        name: "Schützenhalle",
        street: "Dorfstraße 1",
        zip: "48429",
        city: "Rheine"
      })

    {:ok, location} = Calendar.create_location(attrs)
    location
  end

  @doc """
  A published, publicly announced event. `starts_at` defaults to a week from now;
  pass `starts_at:` to control the year/ordering.
  """
  def event_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        status: "published",
        title: "Ein Termin",
        slug: "termin-#{System.unique_integer([:positive])}",
        starts_at: DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.truncate(:second),
        announce: true
      })

    {:ok, event} = Calendar.create_event(attrs)
    event
  end
end
