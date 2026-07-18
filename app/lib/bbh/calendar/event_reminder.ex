defmodule Bbh.Calendar.EventReminder do
  @moduledoc """
  A push reminder for an event, sent `lead_days` before the event starts with a
  custom `text`. `sent_at` guards against sending it more than once.
  """
  use Bbh.Schema

  schema "event_reminders" do
    field :lead_days, :integer
    field :text, :string
    field :sent_at, :utc_datetime

    belongs_to :event, Bbh.Calendar.Event

    timestamps()
  end

  @doc false
  def changeset(reminder, attrs) do
    reminder
    |> cast(attrs, [:lead_days, :text])
    |> validate_required([:lead_days, :text])
    |> validate_number(:lead_days, greater_than_or_equal_to: 0, less_than_or_equal_to: 365)
    |> validate_length(:text, max: 300)
  end
end
