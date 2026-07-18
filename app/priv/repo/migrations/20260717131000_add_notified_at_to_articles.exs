defmodule Bbh.Repo.Migrations.AddNotifiedAtToArticles do
  use Ecto.Migration

  def up do
    alter table(:articles) do
      add :notified_at, :utc_datetime
    end

    # Backfill existing published articles so the new publish-notifier cron does
    # not retroactively push a "Neuer Artikel" notification for old content.
    execute """
    UPDATE articles SET notified_at = NOW() WHERE status = 'published'
    """
  end

  def down do
    alter table(:articles) do
      remove :notified_at
    end
  end
end
