defmodule Bbh.Repo.Migrations.TicketReplies do
  use Ecto.Migration

  # Replies from the Postfach (Bbh.Workers.TicketReplySender): when an outbound message
  # actually left, and — for inbound mail — the raw Message-ID header, encrypted, so a
  # reply can name it in In-Reply-To/References. (`message_id` keeps only its hash, for
  # the idempotent import.)
  def change do
    alter table(:ticket_messages) do
      add :sent_at, :utc_datetime
      add :header_message_id_enc, :binary
    end
  end
end
