defmodule Bbh.Analytics.IcalFetchCount do
  @moduledoc """
  iCal feed retrievals of one day and client family, kept after the day's
  `Bbh.Analytics.IcalFetch` hash rows have been rolled up and deleted (see
  `Bbh.Analytics.roll_up/1`). `clients` is the number of distinct clients that day
  (the rows that were counted), `fetches` their summed polls.
  """
  use Ecto.Schema

  schema "analytics_ical_fetch_counts" do
    field :day, :date
    field :client, :string
    field :clients, :integer
    field :fetches, :integer
  end
end
