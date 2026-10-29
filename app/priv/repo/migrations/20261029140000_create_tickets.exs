defmodule Bbh.Repo.Migrations.CreateTickets do
  use Ecto.Migration

  # The Postfach (Bbh.Tickets). Personal data only in *_enc columns (Bbh.Vault);
  # plain columns carry what lists, filters, reminders and retention need.
  def change do
    execute "CREATE SEQUENCE ticket_number_seq", "DROP SEQUENCE ticket_number_seq"

    create table(:tickets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :number, :integer, null: false, default: fragment("nextval('ticket_number_seq')")
      add :queue, :string, null: false
      add :kind, :string, null: false
      add :status, :string, null: false, default: "new"
      add :assignee_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :follow_up_on, :date
      add :last_activity_at, :utc_datetime, null: false
      add :closed_at, :utc_datetime
      add :deleted_at, :utc_datetime
      add :subject_enc, :binary
      add :requester_name_enc, :binary
      add :requester_email_enc, :binary
      add :requester_email_hmac, :binary
      add :payload_enc, :binary
      add :spam_score, :float
      timestamps(type: :utc_datetime)
    end

    create unique_index(:tickets, [:number])
    create index(:tickets, [:queue, :status])
    create index(:tickets, [:assignee_id])
    create index(:tickets, [:requester_email_hmac])
    create index(:tickets, [:deleted_at])

    create constraint(:tickets, :tickets_kind_valid,
             check: "kind IN ('contact', 'membership', 'email')"
           )

    create constraint(:tickets, :tickets_status_valid,
             check: "status IN ('new', 'open', 'waiting', 'follow_up', 'closed', 'spam')"
           )

    create constraint(:tickets, :tickets_follow_up_needs_date,
             check: "status <> 'follow_up' OR follow_up_on IS NOT NULL"
           )

    create table(:ticket_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :ticket_id, references(:tickets, type: :binary_id, on_delete: :delete_all), null: false
      add :direction, :string, null: false
      add :author_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :from_enc, :binary
      add :to_enc, :binary
      add :body_enc, :binary
      # Outbound: our own <uuid@domain>. Inbound: SHA-256 of the header value.
      add :message_id, :string
      add :in_reply_to, :string
      add :imap_mailbox, :string
      add :imap_uidvalidity, :bigint
      add :imap_uid, :bigint
      add :server_copy_removed_at, :utc_datetime
      # Microseconds: the thread is ordered by it, and a note can follow within a second.
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:ticket_messages, [:ticket_id, :inserted_at])
    create index(:ticket_messages, [:message_id])

    create unique_index(:ticket_messages, [:imap_mailbox, :imap_uidvalidity, :imap_uid],
             where: "imap_uid IS NOT NULL"
           )

    create unique_index(:ticket_messages, [:message_id],
             where: "direction = 'in' AND message_id IS NOT NULL",
             name: :ticket_messages_inbound_message_id_index
           )

    create constraint(:ticket_messages, :ticket_messages_direction_valid,
             check: "direction IN ('in', 'out', 'note', 'system')"
           )

    create table(:ticket_attachments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :ticket_message_id,
          references(:ticket_messages, type: :binary_id, on_delete: :delete_all),
          null: false

      add :filename_enc, :binary
      # As sent; informational only — downloads are always application/octet-stream.
      add :content_type, :string
      add :size, :integer, null: false
      add :data_enc, :binary
      add :inserted_at, :utc_datetime, null: false
    end

    create index(:ticket_attachments, [:ticket_message_id])

    # History and access log. Never personal data in meta. Kept after a purge with the
    # number only (ticket_id nilified).
    create table(:ticket_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :ticket_id, references(:tickets, type: :binary_id, on_delete: :nilify_all)
      add :ticket_number, :integer
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :action, :string, null: false
      add :meta, :map, null: false, default: %{}
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:ticket_events, [:ticket_id, :inserted_at])
    create index(:ticket_events, [:inserted_at])
  end
end
