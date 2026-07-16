defmodule Bbh.Repo.Migrations.AddCountdownSettingsToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      add :show_countdown, :boolean, null: false, default: true
      add :countdown_lead_days, :integer, null: false, default: 60
    end
  end
end
