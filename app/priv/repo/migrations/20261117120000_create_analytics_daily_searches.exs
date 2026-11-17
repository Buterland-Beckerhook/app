defmodule Bbh.Repo.Migrations.CreateAnalyticsDailySearches do
  use Ecto.Migration

  def change do
    # Aggregated site-search terms (one row per day+normalized term), recorded by
    # BbhWeb.Plugs.TrackPageView for the first result page of a /suche query.
    # `no_results` counts the searches of that term that found nothing.
    create table(:analytics_daily_searches) do
      add :day, :date, null: false
      add :term, :string, null: false
      add :searches, :integer, null: false, default: 0
      add :no_results, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:analytics_daily_searches, [:day, :term])
  end
end
