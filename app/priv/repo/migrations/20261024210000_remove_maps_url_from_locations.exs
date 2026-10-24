defmodule Bbh.Repo.Migrations.RemoveMapsUrlFromLocations do
  use Ecto.Migration

  # Map links are derived from lat/lng (OpenStreetMap) now; the stored Google Maps
  # URL is no longer read anywhere.
  def change do
    alter table(:locations) do
      remove :maps_url, :string
    end
  end
end
