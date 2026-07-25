defmodule Bbh.Calendar do
  @moduledoc "Read/query API for events and locations."
  import Ecto.Query
  alias Bbh.Repo
  alias Bbh.Calendar.{CalendarShare, Event, EventReminder, Location}

  @doc "The next upcoming public event (published, announced, no internal calendar)."
  def next_event(now \\ Bbh.Time.now()) do
    Repo.one(
      from e in public_events(),
        where: e.starts_at >= ^now,
        order_by: [asc: e.starts_at],
        limit: 1,
        preload: [:location]
    )
  end

  @doc "All public events for a given year, chronological."
  def list_events_by_year(year) do
    Repo.all(
      from e in public_events(),
        where: e.year == ^year,
        order_by: [asc: e.starts_at],
        preload: [:location]
    )
  end

  @doc "A single public event by slug + year, with location and sub-events."
  def get_public_event(slug, year) do
    Repo.one(
      from e in public_events(),
        where: e.slug == ^slug and e.year == ^year,
        preload: [:location, children: ^from(c in Event, order_by: c.starts_at)]
    )
  end

  @doc "All public events (for the iCal feed)."
  def all_public_events do
    Repo.all(from e in public_events(), order_by: [asc: e.starts_at], preload: [:location])
  end

  @doc "Distinct years that have public events (for the year navigation)."
  def event_years do
    Repo.all(from e in public_events(), distinct: true, select: e.year, order_by: [desc: e.year])
  end

  # Public = published, publicly announced, not on an internal calendar.
  defp public_events do
    from e in Event, where: e.status == "published" and e.announce == true and is_nil(e.calendar)
  end

  ## Admin CRUD — locations

  def list_locations, do: Repo.all(from l in Location, order_by: l.name)
  def get_location!(id), do: Repo.get!(Location, id)
  def create_location(attrs), do: %Location{} |> Location.changeset(attrs) |> Repo.insert()

  def update_location(%Location{} = loc, attrs),
    do: loc |> Location.changeset(attrs) |> Repo.update()

  def delete_location(%Location{} = loc), do: Repo.delete(loc)
  def change_location(%Location{} = loc, attrs \\ %{}), do: Location.changeset(loc, attrs)

  @doc "Locations as {name, id} tuples for a form select."
  def location_options do
    Repo.all(from l in Location, order_by: l.name, select: {l.name, l.id})
  end

  ## Admin CRUD — events

  def list_events,
    do: Repo.all(from e in Event, order_by: [desc: e.starts_at], preload: [:location])

  @doc """
  Events a staff user may manage: admins see all; editors see public events plus any
  calendars granted to them; everyone else (calendar editors) sees only granted calendars.
  """
  def list_events_for(user) do
    from(e in Event, order_by: [desc: e.starts_at], preload: [:location])
    |> scope_events(user)
    |> Repo.all()
  end

  defp scope_events(query, %{role: "admin"}), do: query

  defp scope_events(query, %{role: "editor", calendars: cals}),
    do: from(e in query, where: is_nil(e.calendar) or e.calendar in ^(cals || []))

  defp scope_events(query, %{calendars: cals}),
    do: from(e in query, where: e.calendar in ^(cals || []))

  def count_events, do: Repo.aggregate(Event, :count, :id)

  def get_event!(id) do
    Event
    |> Repo.get!(id)
    |> Repo.preload([
      :location,
      reminders: from(r in EventReminder, order_by: [desc: r.lead_days])
    ])
  end

  def create_event(attrs),
    do: %Event{} |> Event.changeset(attrs) |> Repo.insert() |> Bbh.Search.reindex_after()

  def update_event(%Event{} = e, attrs),
    do: e |> Event.changeset(attrs) |> Repo.update() |> Bbh.Search.reindex_after()

  def delete_event(%Event{} = e), do: e |> Repo.delete() |> Bbh.Search.reindex_after()
  def change_event(%Event{} = e, attrs \\ %{}), do: Event.changeset(e, attrs)

  ## Calendar shares — revocable per-recipient links to an internal calendar

  @doc """
  Creates a share for an internal `calendar` and returns `{:ok, {plaintext, share}}`.

  The plaintext token is only available here (never re-derivable from the stored
  hash) — hand it to the recipient via the share URL. `created_by` is the granting
  user (or `nil`). `attrs` may carry `:recipient_label` and `:expires_at`.
  """
  def create_share(calendar, attrs, created_by) do
    {plaintext, hash} = CalendarShare.build_token()

    params =
      attrs
      |> Map.new()
      |> Map.merge(%{
        calendar: calendar,
        token: hash,
        created_by_id: created_by && created_by.id
      })

    case %CalendarShare{} |> CalendarShare.changeset(params) |> Repo.insert() do
      {:ok, share} -> {:ok, {plaintext, share}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Shares for one internal calendar, or for a list of calendars, newest first.
  """
  def list_shares(calendars) when is_list(calendars) do
    Repo.all(
      from s in CalendarShare, where: s.calendar in ^calendars, order_by: [desc: s.inserted_at]
    )
  end

  def list_shares(calendar) do
    Repo.all(
      from s in CalendarShare, where: s.calendar == ^calendar, order_by: [desc: s.inserted_at]
    )
  end

  @doc """
  Mints a fresh token for an existing share, returning `{:ok, {plaintext, share}}`.

  The previous link stops working immediately (only the new hash is stored). Used
  by "resend": the recipient/calendar/expiry are kept, `last_used_at` is cleared.
  """
  def rotate_share_token(%CalendarShare{} = share) do
    {plaintext, hash} = CalendarShare.build_token()

    case share
         |> Ecto.Changeset.change(token: hash, last_used_at: nil)
         |> Ecto.Changeset.unique_constraint(:token)
         |> Repo.update() do
      {:ok, share} -> {:ok, {plaintext, share}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc "Revokes a share by id. Idempotent — keeps the original revocation time."
  def revoke_share(id) do
    share = Repo.get!(CalendarShare, id)

    if share.revoked_at do
      {:ok, share}
    else
      share |> Ecto.Changeset.change(revoked_at: Bbh.Time.now()) |> Repo.update()
    end
  end

  @doc """
  Resolves a plaintext share token to its share, or `:error`.

  Rejects revoked, expired, unknown and malformed tokens. On success the share's
  `last_used_at` is stamped.
  """
  def verify_share_token(plaintext) do
    with {:ok, hash} <- CalendarShare.hash_token(plaintext),
         %CalendarShare{} = share <- Repo.get_by(CalendarShare, token: hash),
         true <- CalendarShare.active?(share),
         {:ok, share} <-
           share |> Ecto.Changeset.change(last_used_at: Bbh.Time.now()) |> Repo.update() do
      {:ok, share}
    else
      _ -> :error
    end
  end

  @doc """
  Published events of one internal calendar, chronological — the read model behind
  a share's iCal feed. Deliberately separate from the public `is_nil(calendar)`
  gate so sharing never widens what counts as public.
  """
  def shared_calendar_events(calendar) do
    Repo.all(
      from e in Event,
        where: e.calendar == ^calendar and e.status == "published",
        order_by: [asc: e.starts_at],
        preload: [:location]
    )
  end

  @doc """
  Emails the share link to `share.recipient_label` when it looks like an address.

  Returns `{:ok, email}`, `{:error, reason}` from the mailer, or `:skip` when the
  label is not an email.
  """
  def deliver_share_link(%CalendarShare{recipient_label: label} = share, webcal_url, https_url) do
    if CalendarShare.emailable?(share) do
      Bbh.Calendar.ShareNotifier.deliver_calendar_share_instructions(
        label,
        Event.calendar_label(share.calendar),
        webcal_url,
        https_url
      )
    else
      :skip
    end
  end

  ## Event reminders (push notifications ahead of an event)

  @doc """
  Reminders that are due to be sent: not yet sent, whose event is still a
  public, upcoming, published event, and whose lead time has been reached
  (`starts_at - lead_days <= now`). Preloads the event.
  """
  def due_reminders(now \\ Bbh.Time.now()) do
    Repo.all(
      from r in EventReminder,
        join: e in assoc(r, :event),
        where:
          is_nil(r.sent_at) and e.status == "published" and e.announce == true and
            is_nil(e.calendar) and e.starts_at > ^now and
            fragment("? - make_interval(days => ?) <= ?", e.starts_at, r.lead_days, ^now),
        preload: [event: e]
    )
  end

  @doc "Mark a reminder as sent so it is not delivered again."
  def mark_reminder_sent(%EventReminder{} = reminder) do
    reminder
    |> Ecto.Changeset.change(sent_at: Bbh.Time.now())
    |> Repo.update()
  end
end
