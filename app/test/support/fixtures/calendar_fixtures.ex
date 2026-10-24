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

  @doc """
  A published festival: all-day, Sat 20 – Tue 23 July 2030 unless overridden. Pass
  `starts_at:`/`ends_at:` to move it.
  """
  def festival_fixture(attrs \\ %{}) do
    attrs
    |> Enum.into(%{
      title: "Schützenfest",
      slug: "schuetzenfest-#{System.unique_integer([:positive])}",
      all_day: true,
      starts_at: ~U[2030-07-20 00:00:00Z],
      ends_at: ~U[2030-07-23 00:00:00Z]
    })
    |> event_fixture()
  end

  @doc """
  A published programme item of `parent`, Sunday 10:00–11:00 of a
  `festival_fixture/1` unless overridden.
  """
  def programme_item_fixture(parent, attrs \\ %{}) do
    attrs
    |> Enum.into(%{
      parent_id: parent.id,
      title: "Programmpunkt",
      slug: "punkt-#{System.unique_integer([:positive])}",
      starts_at: ~U[2030-07-21 10:00:00Z],
      ends_at: ~U[2030-07-21 11:00:00Z]
    })
    |> event_fixture()
  end

  @doc """
  A calendar share. Returns the `%CalendarShare{}`; pass `calendar:` (default
  `"vorstand"`), `recipient_label:` and `expires_at:` to control it. Use
  `share_with_token/1` when you need the plaintext token too.
  """
  def calendar_share_fixture(attrs \\ %{}) do
    {_plaintext, share} = share_with_token(attrs)
    share
  end

  @doc "Like `calendar_share_fixture/1` but returns `{plaintext_token, share}`."
  def share_with_token(attrs \\ %{}) do
    {calendar, attrs} = Map.pop(Map.new(attrs), :calendar, "vorstand")
    {:ok, {plaintext, share}} = Calendar.create_share(calendar, attrs, attrs[:created_by])
    {plaintext, share}
  end
end
