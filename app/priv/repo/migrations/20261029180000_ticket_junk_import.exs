defmodule Bbh.Repo.Migrations.TicketJunkImport do
  use Ecto.Migration

  # Optional import of the Junk folder (TICKET_IMPORT_JUNK): the poller remembers the
  # highest Junk UID it has looked at, per UIDVALIDITY, so it never re-reads the folder.
  def change do
    alter table(:site_settings) do
      add :ticket_junk_uidvalidity, :bigint
      add :ticket_junk_last_uid, :bigint
    end
  end
end
