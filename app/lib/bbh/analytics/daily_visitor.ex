defmodule Bbh.Analytics.DailyVisitor do
  @moduledoc "One row per distinct visitor per day (daily-salted, non-reversible hash)."
  use Ecto.Schema

  @timestamps_opts [type: :utc_datetime, updated_at: false]

  schema "analytics_daily_visitors" do
    field :day, :date
    field :visitor_hash, :string

    timestamps()
  end
end
