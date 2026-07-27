defmodule Bbh.Calendar.EventReminder do
  @moduledoc """
  A push reminder for an event. Scheduling is either **relative** (`lead_days`
  before the event starts) or **absolute** (`scheduled_at`) — exactly one of the
  two is set. `text` is optional; when blank the notifier falls back to the event
  title, and the push always deep-links to the event. `sent_at` guards against
  sending it more than once.
  """
  use Bbh.Schema

  schema "event_reminders" do
    field :lead_days, :integer
    field :scheduled_at, :utc_datetime
    field :text, :string
    field :sent_at, :utc_datetime

    belongs_to :event, Bbh.Calendar.Event

    timestamps()
  end

  @doc false
  def changeset(reminder, attrs) do
    reminder
    |> cast(attrs, [:lead_days, :scheduled_at, :text])
    |> validate_number(:lead_days, greater_than_or_equal_to: 0, less_than_or_equal_to: 365)
    |> validate_length(:text, max: 300)
    |> validate_one_schedule()
    |> check_constraint(:lead_days,
      name: :event_reminders_one_schedule,
      message: "Entweder Vorlauftage oder ein Datum angeben"
    )
  end

  # Exactly one scheduling mode: relative lead_days or an absolute scheduled_at.
  defp validate_one_schedule(changeset) do
    lead = get_field(changeset, :lead_days)
    at = get_field(changeset, :scheduled_at)

    case {lead, at} do
      {nil, nil} -> add_error(changeset, :lead_days, "Vorlauftage oder Datum angeben")
      {l, a} when not is_nil(l) and not is_nil(a) -> both_set_error(changeset)
      _ -> changeset
    end
  end

  defp both_set_error(changeset) do
    changeset
    |> add_error(:lead_days, "nicht zusammen mit einem Datum angeben")
    |> add_error(:scheduled_at, "nicht zusammen mit Vorlauftagen angeben")
  end
end
