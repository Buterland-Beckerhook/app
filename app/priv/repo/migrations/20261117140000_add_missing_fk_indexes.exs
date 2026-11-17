defmodule Bbh.Repo.Migrations.AddMissingFkIndexes do
  use Ecto.Migration

  # Foreign keys whose `ON DELETE` (nilify) and lookups scanned the whole table:
  # deleting a user — routine since the scheduled deletion — touches the three user
  # references, and the page tree and page deletion look up `pages.parent_id`.
  # The tables are small, so a plain (locking) index build is fine.
  def change do
    create index(:pages, [:parent_id])
    create index(:ticket_messages, [:author_id])
    create index(:ticket_events, [:user_id])
    create index(:queue_grants, [:granted_by_id])
  end
end
