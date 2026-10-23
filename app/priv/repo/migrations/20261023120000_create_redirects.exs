defmodule Bbh.Repo.Migrations.CreateRedirects do
  use Ecto.Migration

  def change do
    # Editor-managed redirects, consulted only for requests that would otherwise 404.
    create table(:redirects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      # Normalized (decoded, lowercase, no trailing slash). A trailing "/*" makes it a
      # prefix rule: "/tags/*" matches "/tags" and everything below it.
      add :source_path, :text, null: false
      # A site path ("/aktuell") or an absolute http(s) URL.
      add :target, :text, null: false
      add :permanent, :boolean, null: false, default: true
      add :note, :text
      add :hits, :integer, null: false, default: 0
      add :last_hit_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:redirects, [:source_path])

    # Paths that ended in a 404, aggregated per normalized path, so missing redirects
    # surface in the admin instead of being guessed at.
    create table(:not_found_paths, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :path, :text, null: false
      add :hits, :integer, null: false, default: 1
      # Last external referrer, host + path only (no query string).
      add :referrer, :text
      add :first_seen_at, :utc_datetime, null: false
      add :last_seen_at, :utc_datetime, null: false
    end

    create unique_index(:not_found_paths, [:path])
    create index(:not_found_paths, [:last_seen_at])
  end
end
