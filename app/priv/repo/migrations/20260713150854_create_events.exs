defmodule Bbh.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :status, :string, null: false, default: "draft"
      add :title, :string, null: false
      add :slug, :string, null: false
      add :start, :utc_datetime, null: false
      add :end, :utc_datetime
      # Derived from start in the changeset (was a DB trigger in Directus).
      add :year, :integer, null: false
      add :all_day, :boolean, null: false, default: false
      add :body, :text
      add :cancel_reason, :string
      add :announce, :boolean, null: false, default: true
      add :revision, :integer
      add :enable_ical, :boolean, null: false, default: true
      # Internal calendar; NULL = public. vorstand|offiziere|jungschuetzen|kinderfest
      add :calendar, :string
      add :location_id, references(:locations, type: :binary_id, on_delete: :nilify_all)
      add :parent_id, references(:events, type: :binary_id, on_delete: :nilify_all)
      add :image_id, references(:media, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:events, [:slug, :year], name: :events_slug_year_unique)
    create index(:events, [:status, :announce, :start])
    create index(:events, [:status, :slug, :year])
    create index(:events, [:parent_id])
    create index(:events, [:location_id])
    create index(:events, [:image_id])

    create constraint(:events, :events_end_after_start,
             check: ~s{"end" IS NULL OR "end" >= "start"}
           )

    create constraint(:events, :events_year_range, check: "year >= 1900")
  end
end
