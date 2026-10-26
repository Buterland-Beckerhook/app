defmodule Bbh.Calendar.Event do
  @moduledoc """
  Calendar event (Termin). `starts_at`/`ends_at` map to the `start`/`end` columns.

  An event can be a **festival** with **programme items** (`parent_id`), one level
  deep: the Schützenfest is entered once, all-day across its days, and every item
  (Gottesdienst, Festumzug, …) as a timed child. Children inherit the parent's
  calendar and never get a countdown or a "Neuer Termin" push of their own; they are
  publicly visible when they are published or canceled *and* their parent is public
  (see `Bbh.Calendar`).
  """
  use Bbh.Schema
  import Ecto.Query, only: [from: 2]

  @statuses ~w(draft published canceled)
  @calendars ~w(vorstand offiziere jungschuetzen kinderfest)

  @calendar_labels %{
    "vorstand" => "Vorstand",
    "offiziere" => "Offiziere",
    "jungschuetzen" => "Jungschützen",
    "kinderfest" => "Kinderfest"
  }

  # Overnight grace for programme items: the last festival day's Festball/Kehraus may
  # run past midnight, until this hour on the following morning.
  @overnight_grace_hours 6

  # Child statuses that are publicly visible (under a public parent). Canceled items
  # stay on the programme, marked "Abgesagt"; drafts let the programme be prepared
  # before it is published.
  @visible_child_statuses ~w(published canceled)

  def statuses, do: @statuses
  def visible_child_statuses, do: @visible_child_statuses
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
    # Shown on the site only when true; iCal always gets the end (see Bbh.ICal).
    field :show_end, :boolean, default: true
    field :countdown_lead_days, :integer, default: 60
    field :calendar, :string
    # Marker for the "Neuer Termin" push; set once sent (see EventPublishNotifier).
    # System-managed, so it is never cast from form params.
    field :notified_at, :utc_datetime
    # Number of visible programme items, filled by listings that need it.
    field :child_count, :integer, virtual: true, default: 0

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
      :show_end,
      :countdown_lead_days,
      :calendar,
      :location_id,
      :parent_id,
      :image_id
    ])
    |> update_change(:body, &Bbh.Html.sanitize/1)
    |> validate_required([:status, :title, :slug, :starts_at])
    |> Bbh.Slug.validate()
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
    |> validate_parent()
    |> validate_children_fit()
    |> reset_internal_public_fields()
    |> unique_constraint([:slug, :year], name: :events_slug_year_unique)
    |> unique_constraint(:slug,
      name: :events_parent_slug_unique,
      message: "ist in diesem Programm schon vergeben"
    )
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

  # A programme item: the parent must be a top-level all-day festival spanning several
  # days, and the item a timed slot within it (plus the overnight grace). The calendar
  # is copied from the parent rather than trusted from the form.
  defp validate_parent(changeset) do
    case get_field(changeset, :parent_id) do
      nil ->
        changeset

      parent_id ->
        parent = Bbh.Repo.get(__MODULE__, parent_id)

        cond do
          is_nil(parent) ->
            add_error(changeset, :parent_id, "existiert nicht")

          parent.id == changeset.data.id ->
            add_error(changeset, :parent_id, "kann nicht der Termin selbst sein")

          not is_nil(parent.parent_id) ->
            add_error(changeset, :parent_id, "ist selbst ein Programmpunkt")

          not festival?(parent) ->
            add_error(changeset, :parent_id, "muss ganztägig sein und mehrere Tage umfassen")

          has_children?(changeset.data) ->
            add_error(changeset, :parent_id, "geht nicht: der Termin hat selbst Programmpunkte")

          true ->
            changeset
            |> put_change(:calendar, parent.calendar)
            |> validate_child_shape(parent)
            |> put_child_defaults()
        end
    end
  end

  defp validate_child_shape(changeset, parent) do
    starts_at = get_field(changeset, :starts_at)
    ends_at = get_field(changeset, :ends_at)

    cond do
      get_field(changeset, :all_day) ->
        add_error(changeset, :all_day, "geht nicht für Programmpunkte – bitte Uhrzeiten angeben")

      is_nil(ends_at) ->
        add_error(changeset, :ends_at, "muss für Programmpunkte gesetzt sein")

      is_nil(starts_at) ->
        changeset

      DateTime.compare(starts_at, festival_opens(parent)) == :lt ->
        add_error(changeset, :starts_at, "liegt vor dem ersten Festtag")

      DateTime.compare(ends_at, festival_closes(parent)) == :gt ->
        add_error(
          changeset,
          :ends_at,
          "liegt nach dem Ende des Festes (#{@overnight_grace_hours}:00 Uhr am Folgetag)"
        )

      true ->
        changeset
    end
  end

  # Belt and braces against the publish push: a programme item never counts down and
  # is marked notified, so even a path that forgets the parent_id check stays quiet.
  defp put_child_defaults(changeset) do
    changeset = put_change(changeset, :show_countdown, false)

    if get_field(changeset, :notified_at),
      do: changeset,
      else: put_change(changeset, :notified_at, Bbh.Time.now())
  end

  # A festival with programme items must stay a festival that still contains them.
  # Only checked when its dates change, so a plain edit costs no query.
  defp validate_children_fit(changeset) do
    relevant? = Enum.any?([:starts_at, :ends_at, :all_day, :parent_id], &changed?(changeset, &1))

    if relevant? and is_nil(get_field(changeset, :parent_id)) and changeset.valid? and
         has_children?(changeset.data) do
      check_children_fit(changeset)
    else
      changeset
    end
  end

  defp check_children_fit(changeset) do
    fest = %{
      all_day: get_field(changeset, :all_day),
      starts_at: get_field(changeset, :starts_at),
      ends_at: get_field(changeset, :ends_at)
    }

    if festival?(fest) do
      opens = festival_opens(fest)
      closes = festival_closes(fest)

      outside =
        Bbh.Repo.one(
          from c in __MODULE__,
            where:
              c.parent_id == ^changeset.data.id and
                (c.starts_at < ^opens or c.ends_at > ^closes),
            order_by: c.starts_at,
            limit: 1,
            select: c.title
        )

      if outside,
        do: add_error(changeset, :ends_at, "„#{outside}“ läge dann außerhalb des Festes"),
        else: changeset
    else
      add_error(
        changeset,
        :all_day,
        "Ein Termin mit Programmpunkten muss ganztägig sein und mehrere Tage umfassen"
      )
    end
  end

  @doc "Can `event` carry programme items? All-day, ending on a later day than it starts."
  def festival?(%{all_day: true, starts_at: %DateTime{} = s, ends_at: %DateTime{} = e}),
    do: Date.compare(DateTime.to_date(e), DateTime.to_date(s)) == :gt

  def festival?(_), do: false

  @doc """
  Is this top-level event public — published, announced, not on an internal calendar?
  The struct-side twin of the query in `Bbh.Calendar` (for a programme item, its
  festival decides).
  """
  def public?(%{status: "published", announce: true, calendar: nil}), do: true
  def public?(_), do: false

  @doc "Earliest start of a programme item: the festival's first day, 00:00."
  def festival_opens(%{starts_at: s}),
    do: DateTime.new!(DateTime.to_date(s), ~T[00:00:00], "Etc/UTC")

  @doc "Latest end of a programme item: the morning after the last day, at the grace hour."
  def festival_closes(%{ends_at: e}) do
    e
    |> DateTime.to_date()
    |> Date.add(1)
    |> DateTime.new!(Time.new!(@overnight_grace_hours, 0, 0), "Etc/UTC")
  end

  defp has_children?(%__MODULE__{id: nil}), do: false

  defp has_children?(%__MODULE__{id: id}),
    do: Bbh.Repo.exists?(from c in __MODULE__, where: c.parent_id == ^id)

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
