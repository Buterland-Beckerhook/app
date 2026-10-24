defmodule BbhWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use BbhWeb, :html

  embed_templates "page_html/*"

  @month_abbr ~w(Jan Feb Mär Apr Mai Jun Jul Aug Sep Okt Nov Dez)

  # How far ahead the homepage shows a festival's next programme item next to the
  # festival itself. Weeks before, the item would only crowd the announcement.
  @next_child_lead_hours 48

  @doc "Short German month label (Jan, Feb, …) for the date badge."
  def month_abbr(%DateTime{month: month}), do: Enum.at(@month_abbr, month - 1)

  @doc """
  Naive ISO target for the JS countdown (no timezone), so the browser parses it
  as local time — matching how the rest of the site renders event times.
  """
  def countdown_target(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%dT%H:%M:%S")

  @doc """
  Whether to render the countdown timer for an event: enabled per-event, still in
  the future, and within the configured lead window.

  `Bbh.Calendar.next_event/0` now keeps an event on the homepage until it is over,
  so the event may already have started — in that case there is nothing to count
  down to ("Es beginnt in …" would sit at zero), and the countdown is hidden.
  """
  def countdown_visible?(event, now \\ Bbh.Time.now())

  def countdown_visible?(
        %{show_countdown: true, countdown_lead_days: lead, starts_at: %DateTime{} = starts_at},
        now
      )
      when is_integer(lead),
      do: counts_down?(starts_at, lead, now)

  def countdown_visible?(_event, _now), do: false

  @doc """
  Whether the homepage shows a festival's next programme item yet: once it starts
  within #{@next_child_lead_hours} hours (or is already running). Until then only the
  festival is announced — the countdown still counts down to that first item.
  """
  def next_child_shown?(%{starts_at: starts_at}, now \\ Bbh.Time.now()),
    do: DateTime.diff(starts_at, now, :hour) < @next_child_lead_hours

  @doc """
  What the homepage countdown counts down to, as `%{at: DateTime, label: String}`, or
  `nil` to hide it.

  An event without a programme (`first_child` nil): its own start, while
  `countdown_visible?/2`. A festival: until it opens, its opening — the earlier of its
  own start, if that carries a time (an all-day 00:00 does not), and its first item —
  as "Es beginnt in"; once under way, the next item still to start
  (`countdown_child`), as "Nächster Programmpunkt in"; nothing once none is left.
  The festival's own `show_countdown` and `countdown_lead_days` still decide whether
  there is a countdown at all.
  """
  def countdown(event, first_child, countdown_child, now \\ Bbh.Time.now())

  def countdown(nil, _first_child, _countdown_child, _now), do: nil

  def countdown(event, nil, _countdown_child, now) do
    if countdown_visible?(event, now), do: %{at: event.starts_at, label: "Es beginnt in"}
  end

  def countdown(
        %{show_countdown: true, countdown_lead_days: lead} = event,
        first_child,
        countdown_child,
        now
      )
      when is_integer(lead) do
    opening = Enum.min([first_child.starts_at | List.wrap(timed_start(event))], DateTime)

    target =
      cond do
        DateTime.compare(opening, now) == :gt -> %{at: opening, label: "Es beginnt in"}
        countdown_child -> %{at: countdown_child.starts_at, label: "Nächster Programmpunkt in"}
        true -> nil
      end

    if target && counts_down?(target.at, lead, now), do: target
  end

  def countdown(_event, _first_child, _countdown_child, _now), do: nil

  # An event's start as a real moment: an all-day event at 00:00 only names its day.
  defp timed_start(%{all_day: true, starts_at: %DateTime{hour: 0, minute: 0}}), do: nil
  defp timed_start(%{starts_at: starts_at}), do: starts_at

  defp counts_down?(at, lead, now),
    do: DateTime.compare(at, now) == :gt and DateTime.diff(at, now, :day) <= lead
end
