defmodule Bbh.Tickets.Message do
  @moduledoc """
  One entry in a ticket's thread: an inbound mail or form submission (`in`), a reply
  (`out`), an internal note (`note`) or a note by the system (`system`).
  """
  use Ecto.Schema

  @encrypted [
    {:from, :from_enc},
    {:to, :to_enc},
    {:body, :body_enc},
    {:header_message_id, :header_message_id_enc}
  ]

  @doc false
  def encrypted_fields, do: @encrypted

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "ticket_messages" do
    belongs_to :ticket, Bbh.Tickets.Ticket
    belongs_to :author, Bbh.Accounts.User
    field :direction, :string

    field :from, :string, virtual: true, redact: true
    field :to, :string, virtual: true, redact: true
    field :body, :string, virtual: true, redact: true
    field :from_enc, :binary, redact: true
    field :to_enc, :binary, redact: true
    field :body_enc, :binary, redact: true
    # Inbound mail: the raw Message-ID header, for In-Reply-To of a reply.
    field :header_message_id, :string, virtual: true, redact: true
    field :header_message_id_enc, :binary, redact: true

    field :message_id, :string
    field :in_reply_to, :string
    field :imap_mailbox, :string
    field :imap_uidvalidity, :integer
    field :imap_uid, :integer
    field :server_copy_removed_at, :utc_datetime
    # Outbound: when the reply actually left (Bbh.Workers.TicketReplySender).
    field :sent_at, :utc_datetime

    has_many :attachments, Bbh.Tickets.Attachment, foreign_key: :ticket_message_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> Ecto.Changeset.cast(
      attrs,
      [:ticket_id, :author_id, :direction, :from, :to, :body, :header_message_id] ++
        [:message_id, :in_reply_to, :imap_mailbox, :imap_uidvalidity, :imap_uid]
    )
    |> Ecto.Changeset.validate_required([:ticket_id, :direction])
    |> Ecto.Changeset.validate_inclusion(:direction, ~w(in out note system))
  end
end
