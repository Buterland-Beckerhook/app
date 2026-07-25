defmodule Bbh.Repo.Migrations.CreateAnalyticsIcalFetches do
  use Ecto.Migration

  def change do
    # One row per distinct client per day for the public iCal subscription feed.
    # `visitor_hash` is the same daily-salted, non-reversible digest used for
    # visitors; counting rows per day gives rough unique subscribers, summing
    # `fetches` gives total polls.
    create table(:analytics_ical_fetches) do
      add :day, :date, null: false
      add :visitor_hash, :string, null: false
      add :fetches, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:analytics_ical_fetches, [:day, :visitor_hash])
    create index(:analytics_ical_fetches, [:day])
  end
end
