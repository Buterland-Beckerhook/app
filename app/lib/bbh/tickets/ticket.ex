defmodule Bbh.Tickets.Ticket do
  @moduledoc """
  One request in the Postfach. Clear text lives in the virtual fields only; the context
  (`Bbh.Tickets`) encrypts them into the `*_enc` columns and decrypts on load.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Bbh.Tickets.Queue

  @kinds ~w(contact membership email)
  @statuses ~w(new open waiting follow_up closed spam)
  # The statuses a ticket is "in work" with — the default list view.
  @active_statuses ~w(new open waiting follow_up)

  @encrypted [
    {:subject, :subject_enc},
    {:requester_name, :requester_name_enc},
    {:requester_email, :requester_email_enc},
    {:payload, :payload_enc, :map}
  ]

  @doc false
  def encrypted_fields, do: @encrypted

  def kinds, do: @kinds
  def statuses, do: @statuses
  def active_statuses, do: @active_statuses

  @status_labels %{
    "new" => "Neu",
    "open" => "In Bearbeitung",
    "waiting" => "Wartet auf Antwort",
    "follow_up" => "Wiedervorlage",
    "closed" => "Erledigt",
    "spam" => "Spam"
  }

  @doc "German label of a status."
  def status_label(status), do: Map.get(@status_labels, status, status)

  @doc "`{label, status}` options a user may set by hand (`new` is never set by hand)."
  def status_options,
    do: for(s <- ~w(open waiting follow_up closed), do: {status_label(s), s})

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "tickets" do
    field :number, :integer, read_after_writes: true
    field :queue, :string
    field :kind, :string
    field :status, :string, default: "new"
    belongs_to :assignee, Bbh.Accounts.User
    field :follow_up_on, :date
    field :last_activity_at, :utc_datetime
    field :closed_at, :utc_datetime
    field :deleted_at, :utc_datetime
    field :spam_score, :float
    # When the queue was told about it (Bbh.Workers.TicketNewNotifier); nil = not yet.
    field :notified_at, :utc_datetime

    field :subject, :string, virtual: true, redact: true
    field :requester_name, :string, virtual: true, redact: true
    field :requester_email, :string, virtual: true, redact: true
    field :payload, :map, virtual: true, redact: true
    field :subject_enc, :binary, redact: true
    field :requester_name_enc, :binary, redact: true
    field :requester_email_enc, :binary, redact: true
    field :requester_email_hmac, :binary, redact: true
    field :payload_enc, :binary, redact: true

    has_many :messages, Bbh.Tickets.Message, preload_order: [asc: :inserted_at]

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for a new ticket (from a form or an inbound mail)."
  def create_changeset(ticket, attrs) do
    ticket
    |> cast(attrs, [
      :queue,
      :kind,
      :status,
      :subject,
      :requester_name,
      :requester_email,
      :payload,
      :spam_score
    ])
    |> validate_required([:queue, :kind])
    |> validate_inclusion(:queue, Queue.keys())
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:status, ~w(new spam))
    |> put_change(:last_activity_at, DateTime.utc_now(:second))
  end

  @doc "Changeset for a status change; keeps `closed_at` and the follow-up date consistent."
  def status_changeset(ticket, status, follow_up_on) do
    ticket
    |> change(status: status, last_activity_at: DateTime.utc_now(:second))
    |> validate_inclusion(:status, @statuses)
    |> put_change(:follow_up_on, if(status == "follow_up", do: follow_up_on))
    |> validate_follow_up()
    |> put_change(:closed_at, if(status == "closed", do: DateTime.utc_now(:second)))
    |> check_constraint(:status, name: :tickets_follow_up_needs_date)
  end

  defp validate_follow_up(changeset) do
    if get_field(changeset, :status) == "follow_up" and
         is_nil(get_field(changeset, :follow_up_on)),
       do: add_error(changeset, :follow_up_on, "Bitte ein Datum für die Wiedervorlage angeben."),
       else: changeset
  end

  @doc ~s(Display reference, e.g. "BB-2026-0042" — the year is the year it came in.)
  def reference(%__MODULE__{number: number, inserted_at: inserted_at}) do
    year = if inserted_at, do: inserted_at.year, else: Date.utc_today().year
    "BB-#{year}-#{number |> Integer.to_string() |> String.pad_leading(4, "0")}"
  end

  @doc ~s|The number in a reference ("BB-2026-0042", "bb-2026-42" or "42"), or nil.|
  def parse_reference(reference) when is_binary(reference) do
    case Regex.run(~r/^\s*(?:BB-\d{4}-)?0*(\d+)\s*$/i, reference) do
      [_, digits] -> String.to_integer(digits)
      _ -> nil
    end
  end

  def parse_reference(_), do: nil
end
