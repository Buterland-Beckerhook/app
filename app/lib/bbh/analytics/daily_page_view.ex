defmodule Bbh.Analytics.DailyPageView do
  @moduledoc "Per-day page-view counter (day + path)."
  use Ecto.Schema

  @timestamps_opts [type: :utc_datetime]

  schema "analytics_daily_page_views" do
    field :day, :date
    field :path, :string
    field :views, :integer, default: 0

    timestamps()
  end
end
