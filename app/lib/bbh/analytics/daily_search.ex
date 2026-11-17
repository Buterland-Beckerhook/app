defmodule Bbh.Analytics.DailySearch do
  @moduledoc """
  Per-day site-search counter (day + normalized term). `no_results` counts the
  searches of that term that found nothing. Only the term is stored — no visitor hash,
  so it can't be tied to a visit.
  """
  use Ecto.Schema

  @timestamps_opts [type: :utc_datetime]

  schema "analytics_daily_searches" do
    field :day, :date
    field :term, :string
    field :searches, :integer, default: 0
    field :no_results, :integer, default: 0

    timestamps()
  end
end
