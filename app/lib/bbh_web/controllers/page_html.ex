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
  def countdown_visible?(%{
        show_countdown: true,
        countdown_lead_days: lead,
        starts_at: %DateTime{} = starts_at
      })
      when is_integer(lead) do
    now = Bbh.Time.now()

    DateTime.compare(starts_at, now) == :gt and
      DateTime.diff(starts_at, now, :day) <= lead
  end

  def countdown_visible?(_), do: false
end
