defmodule Bbh.Calendar.Event do
  @moduledoc "Calendar event (Termin). `starts_at`/`ends_at` map to the `start`/`end` columns."
  use Bbh.Schema

  @statuses ~w(draft published canceled)
  @calendars ~w(vorstand offiziere jungschuetzen kinderfest)

  @calendar_labels %{
    "vorstand" => "Vorstand",
    "offiziere" => "Offiziere",
    "jungschuetzen" => "Jungschützen",
    "kinderfest" => "Kinderfest"
  }

  def statuses, do: @statuses
  def calendars, do: @calendars
  def calendar_label(calendar), do: Map.get(@calendar_labels, calendar, calendar)

  schema "events" do
    field :status, :string, default: "draft"
    field :title, :string
    field :slug, :string
    field :starts_at, :utc_datetime, source: :start
    field :ends_at, :utc_datetime, source: :end
    field :year, :integer
    field :all_day, :boolean, default: false
    field :body, :string
    field :cancel_reason, :string
    field :announce, :boolean, default: true
    field :revision, :integer
    field :enable_ical, :boolean, default: true
    field :show_countdown, :boolean, default: true
    field :countdown_lead_days, :integer, default: 60
    field :calendar, :string
    # Marker for the "Neuer Termin" push; set once sent (see EventPublishNotifier).
    # System-managed, so it is never cast from form params.
    field :notified_at, :utc_datetime

    belongs_to :location, Bbh.Calendar.Location
    belongs_to :parent, Bbh.Calendar.Event
    belongs_to :image, Bbh.Media.Upload
    has_many :children, Bbh.Calendar.Event, foreign_key: :parent_id
    has_many :reminders, Bbh.Calendar.EventReminder, on_replace: :delete

    timestamps()
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :status,
      :title,
      :slug,
      :starts_at,
      :ends_at,
      :year,
      :all_day,
      :body,
      :cancel_reason,
      :announce,
      :revision,
      :enable_ical,
      :show_countdown,
      :countdown_lead_days,
      :calendar,
      :location_id,
      :parent_id,
      :image_id
    ])
    |> update_change(:body, &Bbh.Html.sanitize/1)
    |> validate_required([:status, :title, :slug, :starts_at])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:calendar, @calendars, message: "ist kein gültiger Kalender")
    |> put_year()
    |> validate_number(:year, greater_than_or_equal_to: 1900)
    |> validate_number(:countdown_lead_days, greater_than_or_equal_to: 0)
    |> cast_assoc(:reminders,
      sort_param: :reminders_sort,
      drop_param: :reminders_drop
    )
    |> reset_internal_public_fields()
    |> put_default_end()
    |> validate_end_after_start()
    |> unique_constraint([:slug, :year], name: :events_slug_year_unique)
    |> foreign_key_constraint(:location_id)
    |> foreign_key_constraint(:parent_id)
    |> foreign_key_constraint(:image_id)
    |> check_constraint(:ends_at,
      name: :events_end_after_start,
      message: "muss nach dem Beginn liegen"
    )
    |> check_constraint(:year,
      name: :events_year_range,
      message: "muss ab 1900 liegen"
    )
  end

  # Internal-calendar events have no public presence — they are only reachable via
  # a shared .ics feed. The public-facing options (public announcement, homepage
  # countdown, push reminders, public iCal download) therefore never apply, so
  # force them off regardless of what the form submitted. `countdown_lead_days`
  # is left at its default — it is inert once `show_countdown` is false.
  defp reset_internal_public_fields(changeset) do
    case get_field(changeset, :calendar) do
      cal when cal in [nil, ""] ->
        changeset

      _internal ->
        changeset
        |> put_change(:announce, false)
        |> put_change(:show_countdown, false)
        |> put_change(:enable_ical, false)
        |> drop_reminders()
    end
  end

  # Replacing reminders with [] is safe on a new (unpersisted) parent and on a
  # persisted parent whose reminders are loaded. Only the persisted-and-unloaded
  # case would raise from put_assoc — skip it (leftover reminders on an internal
  # event are inert; `due_reminders` filters them out anyway).
  defp drop_reminders(changeset) do
    persisted_unloaded? =
      changeset.data.__meta__.state == :loaded and
        match?(%Ecto.Association.NotLoaded{}, changeset.data.reminders)

    if persisted_unloaded?, do: changeset, else: put_assoc(changeset, :reminders, [])
  end

  # A timed event without an explicit end defaults to end of its start day (23:59).
  # Event times are stored as local wall-clock (see Bbh.Time), so the components are
  # set directly. All-day events keep their end untouched — iCal uses only the date
  # and `next_event` already treats them as running through the day.
  defp put_default_end(changeset) do
    ends_at = get_field(changeset, :ends_at)
    all_day = get_field(changeset, :all_day)
    starts_at = get_field(changeset, :starts_at)

    if is_nil(ends_at) and all_day != true and match?(%DateTime{}, starts_at) do
      put_change(changeset, :ends_at, %{starts_at | hour: 23, minute: 59, second: 0})
    else
      changeset
    end
  end

  defp put_year(changeset) do
    case get_field(changeset, :starts_at) do
      %DateTime{year: year} -> put_change(changeset, :year, year)
      _ -> changeset
    end
  end

  defp validate_end_after_start(changeset) do
    starts_at = get_field(changeset, :starts_at)
    ends_at = get_field(changeset, :ends_at)

    if starts_at && ends_at && DateTime.compare(ends_at, starts_at) == :lt do
      add_error(changeset, :ends_at, "muss nach dem Beginn liegen")
    else
      changeset
    end
  end
end
