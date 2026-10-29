defmodule Bbh.Tickets.Attachment do
  @moduledoc """
  A file that came with an inbound mail. Stored encrypted in the database on purpose:
  one encryption path, covered by the nightly dump, deleted with its ticket.
  """
  use Ecto.Schema

  @encrypted [{:filename, :filename_enc}, {:data, :data_enc}]

  @doc false
  def encrypted_fields, do: @encrypted

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "ticket_attachments" do
    belongs_to :ticket_message, Bbh.Tickets.Message
    field :filename, :string, virtual: true, redact: true
    field :data, :binary, virtual: true, redact: true
    field :filename_enc, :binary, redact: true
    field :data_enc, :binary, redact: true
    field :content_type, :string
    field :size, :integer

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
