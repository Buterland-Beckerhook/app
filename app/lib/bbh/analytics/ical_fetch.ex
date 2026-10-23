defmodule Bbh.Analytics.IcalFetch do
  @moduledoc """
  Per-day retrievals of the public iCal subscription feed. One row per distinct
  client per day; `fetches` counts how often that client polled that day. Counting
  rows per day yields rough unique subscribers, summing `fetches` yields total polls.

  `client` is the coarse calendar-client family (`Bbh.Analytics.IcalClient`), never the
  raw User-Agent; `nil` for rows recorded before it was stored.
  """
  use Ecto.Schema

  @timestamps_opts [type: :utc_datetime]

  schema "analytics_ical_fetches" do
    field :day, :date
    field :visitor_hash, :string
    field :fetches, :integer, default: 0
    field :client, :string

    timestamps()
  end
end
