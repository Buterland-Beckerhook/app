defmodule Bbh.Repo.Migrations.CreateAnalyticsDailyCounts do
  use Ecto.Migration

  def change do
    # Daily totals that outlive the per-visitor hashes. The hashes in
    # analytics_daily_visitors / analytics_ical_fetches are pseudonymous (anyone holding
    # secret_key_base could re-derive them per day), so Bbh.Workers.AnalyticsRollup folds
    # every day past the retention window into these counts and deletes the hash rows.
    create table(:analytics_daily_visitor_counts, primary_key: false) do
      add :day, :date, primary_key: true
      add :visitors, :integer, null: false
    end

    # One row per day and client family. `client` stays nullable like on the per-hash
    # table (rows recorded before it existed), so NULLs must not be distinct for the
    # rollup's upsert to find the existing row.
    create table(:analytics_ical_fetch_counts) do
      add :day, :date, null: false
      add :client, :string
      add :clients, :integer, null: false
      add :fetches, :integer, null: false
    end

    create unique_index(:analytics_ical_fetch_counts, [:day, :client], nulls_distinct: false)
  end
end
