defmodule Bbh.Repo.Migrations.AddClientToAnalyticsIcalFetches do
  use Ecto.Migration

  def change do
    # Coarse calendar-client family (see Bbh.Analytics.IcalClient) — never the raw
    # User-Agent. Nullable: rows recorded before this column existed stay NULL and are
    # shown as "Unbekannt".
    alter table(:analytics_ical_fetches) do
      add :client, :string
    end
  end
end
