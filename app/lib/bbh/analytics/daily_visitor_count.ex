defmodule Bbh.Analytics.DailyVisitorCount do
  @moduledoc """
  Unique visitors of one day, kept after the day's `Bbh.Analytics.DailyVisitor` hash
  rows have been rolled up and deleted (see `Bbh.Analytics.roll_up/1`).
  """
  use Ecto.Schema

  @primary_key false
  schema "analytics_daily_visitor_counts" do
    field :day, :date, primary_key: true
    field :visitors, :integer
  end
end
