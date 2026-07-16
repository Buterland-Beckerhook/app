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
end
