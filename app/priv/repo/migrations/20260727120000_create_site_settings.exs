defmodule Bbh.Repo.Migrations.CreateSiteSettings do
  use Ecto.Migration

  # A fixed id for the singleton row so the seed is idempotent and easy to target.
  @singleton_id "00000000-0000-0000-0000-000000000001"

  def up do
    create table(:site_settings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :home_notice_text, :text
      add :home_notice_enabled, :boolean, null: false, default: false
      add :quiet_hours_enabled, :boolean, null: false, default: true
      add :quiet_hours_start, :integer, null: false, default: 22
      add :quiet_hours_end, :integer, null: false, default: 8

      timestamps(type: :utc_datetime)
    end

    # Seed the single settings row so reads always find it.
    execute("""
    INSERT INTO site_settings (id, home_notice_enabled, quiet_hours_enabled, quiet_hours_start, quiet_hours_end, inserted_at, updated_at)
    VALUES ('#{@singleton_id}', false, true, 22, 8, now(), now())
    """)
  end

  def down do
    drop table(:site_settings)
  end
end
