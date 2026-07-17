defmodule Bbh.Repo.Migrations.CreateAnalytics do
  use Ecto.Migration

  def change do
    # Aggregated, PII-free page-view counters (one row per day+path).
    create table(:analytics_daily_page_views) do
      add :day, :date, null: false
      add :path, :string, null: false
      add :views, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:analytics_daily_page_views, [:day, :path])
    create index(:analytics_daily_page_views, [:day])

    # Aggregated external referrer hosts (one row per day+host).
    create table(:analytics_daily_referrers) do
      add :day, :date, null: false
      add :host, :string, null: false
      add :views, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:analytics_daily_referrers, [:day, :host])

    # One row per distinct visitor per day. `visitor_hash` is a non-reversible
    # daily-salted digest (secret_key_base + day + ip + user-agent); counting
    # rows per day yields a rough unique-visitor figure without storing PII.
    create table(:analytics_daily_visitors) do
      add :day, :date, null: false
      add :visitor_hash, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:analytics_daily_visitors, [:day, :visitor_hash])
    create index(:analytics_daily_visitors, [:day])
  end
end
