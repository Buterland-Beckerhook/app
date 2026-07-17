defmodule Bbh.Analytics.DailyReferrer do
  @moduledoc "Per-day external-referrer counter (day + host)."
  use Ecto.Schema

  @timestamps_opts [type: :utc_datetime]

  schema "analytics_daily_referrers" do
    field :day, :date
    field :host, :string
    field :views, :integer, default: 0

    timestamps()
  end
end
