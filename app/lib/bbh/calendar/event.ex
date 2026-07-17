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
