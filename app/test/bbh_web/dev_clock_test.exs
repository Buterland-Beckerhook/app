defmodule BbhWeb.DevClockTest do
  use ExUnit.Case, async: true

  alias BbhWeb.DevClock

  # Sat 18 – Tue 21 July 2026, as in the demo Schützenfest.
  @fest %{starts_at: ~U[2026-07-18 00:00:00Z], ends_at: ~U[2026-07-21 00:00:00Z], children: []}

  defp item(title, starts_at, ends_at),
    do: %{title: title, starts_at: starts_at, ends_at: ends_at}

  defp times(points), do: Enum.map(points, & &1.at)

  test "no festival, no jump points" do
    assert DevClock.jump_points(nil) == []
    assert DevClock.overview_points(nil) == []
  end

  test "without programme items, falls back to fixed times on the festival's days" do
    points = times(DevClock.jump_points(@fest))

    assert hd(points) == ~U[2026-07-11 12:00:00Z]
    assert ~U[2026-07-20 01:30:00Z] in points
    assert ~U[2026-07-22 01:59:00Z] in points
    assert ~U[2026-07-22 02:01:00Z] in points
    assert List.last(points) == ~U[2026-07-22 12:00:00Z]
    assert points == Enum.sort(points, DateTime)
  end

  test "with programme items, derives the moments from them" do
    children = [
      item("Kinderfest", ~U[2026-07-18 14:00:00Z], ~U[2026-07-18 18:00:00Z]),
      item("Tanz", ~U[2026-07-18 20:00:00Z], ~U[2026-07-19 02:00:00Z]),
      item("Gottesdienst", ~U[2026-07-19 09:30:00Z], ~U[2026-07-19 10:30:00Z]),
      item("Kehraus", ~U[2026-07-21 20:00:00Z], ~U[2026-07-22 02:00:00Z])
    ]

    points = DevClock.jump_points(%{@fest | children: children})
    at = times(points)

    assert hd(at) == ~U[2026-07-11 12:00:00Z]
    # just before and during the first item
    assert ~U[2026-07-18 13:59:00Z] in at
    assert ~U[2026-07-18 16:00:00Z] in at
    # five minutes before each later day's first item
    assert ~U[2026-07-19 09:25:00Z] in at
    assert ~U[2026-07-21 19:55:00Z] in at
    # inside the first overnight item
    assert ~U[2026-07-19 01:30:00Z] in at
    # around the last item's end, then the day after
    assert ~U[2026-07-22 01:59:00Z] in at
    assert ~U[2026-07-22 02:01:00Z] in at
    assert List.last(at) == ~U[2026-07-22 12:00:00Z]

    overview = times(DevClock.overview_points(%{@fest | children: children}))
    assert ~U[2026-07-19 09:30:00Z] in overview
    assert ~U[2026-07-19 09:31:00Z] in overview
    assert ~U[2026-07-19 10:30:00Z] in overview
    assert overview == Enum.uniq(overview)
  end

  test "param/1 is the ?jetzt= format" do
    assert DevClock.param(~U[2026-07-19 09:25:00Z]) == "2026-07-19T09:25"
  end
end
