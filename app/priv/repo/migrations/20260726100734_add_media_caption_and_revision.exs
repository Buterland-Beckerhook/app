defmodule Bbh.Repo.Migrations.AddMediaCaptionAndRevision do
  use Ecto.Migration

  def change do
    alter table(:media) do
      # Bildunterschrift — shown under the image on the public site. Distinct from
      # `title` (library label) and `description` (alt text).
      add :caption, :string
      # Bumped whenever the stored original changes (rotation). Rides along on media
      # URLs as `?v=` so a browser cache (max-age=604800) cannot keep serving the old
      # orientation; the server-side variant cache is purged outright.
      add :revision, :integer, null: false, default: 0
    end
  end
end
