defmodule BbhWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use BbhWeb, :html

  embed_templates "page_html/*"

  @month_abbr ~w(Jan Feb Mär Apr Mai Jun Jul Aug Sep Okt Nov Dez)

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
  What the homepage countdown counts down to, as `%{at: DateTime, label: String}`, or
  `nil` to hide it.

  An event without a programme (`next_child` nil): its own start, while
  `countdown_visible?/2`. A festival: the next programme item that has not started
  yet (`countdown_child`) — if the shown item is already running, the one after it;
  once none is left, nothing. The festival's own `show_countdown` and
  `countdown_lead_days` still decide whether there is a countdown at all.
  """
  def countdown(event, next_child, countdown_child, now \\ Bbh.Time.now())

  def countdown(nil, _next_child, _countdown_child, _now), do: nil

  def countdown(event, nil, _countdown_child, now) do
    if countdown_visible?(event, now), do: %{at: event.starts_at, label: "Es beginnt in"}
  end

  def countdown(_event, _next_child, nil, _now), do: nil

  def countdown(
        %{show_countdown: true, countdown_lead_days: lead} = event,
        _next_child,
        %{starts_at: at},
        now
      )
      when is_integer(lead) do
    if counts_down?(at, lead, now) do
      label =
        if DateTime.compare(now, event.starts_at) == :lt,
          do: "Es beginnt in",
          else: "Nächster Programmpunkt in"

      %{at: at, label: label}
    end
  end

  def countdown(_event, _next_child, _countdown_child, _now), do: nil

  defp counts_down?(at, lead, now),
    do: DateTime.compare(at, now) == :gt and DateTime.diff(at, now, :day) <= lead
end
