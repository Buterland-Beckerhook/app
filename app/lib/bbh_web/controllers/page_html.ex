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
  Whether to render the countdown timer for an event: enabled per-event and within
  the configured lead window. `starts_at >= now` is already guaranteed by
  `Bbh.Calendar.next_event/0`, so only the upper (lead-days) bound is checked.
  """
  def countdown_visible?(%{
        show_countdown: true,
        countdown_lead_days: lead,
        starts_at: %DateTime{} = starts_at
      })
      when is_integer(lead) do
    DateTime.diff(starts_at, Bbh.Time.now(), :day) <= lead
  end

  def countdown_visible?(_), do: false
end
