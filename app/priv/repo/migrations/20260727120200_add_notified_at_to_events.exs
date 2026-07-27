defmodule Bbh.Repo.Migrations.AddNotifiedAtToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      # Marker for the "Neuer Termin" push, mirroring articles.notified_at: set once
      # the publish notification has been sent so it is never sent twice.
      add :notified_at, :utc_datetime
    end

    # Backfill: existing published events must not trigger a retroactive push flood
    # when the notifier first runs, so treat them as already notified.
    execute(
      "UPDATE events SET notified_at = now() WHERE status = 'published'",
      ""
    )
  end
end
