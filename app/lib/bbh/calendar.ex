defmodule Bbh.Calendar do
  @moduledoc "Read/query API for events and locations."
  import Ecto.Query
  alias Bbh.Repo
  alias Bbh.Calendar.{CalendarShare, Event, EventReminder, Location}

  @doc """
  The next public event to highlight (published, announced, no internal calendar).

  An event stays selected until it is over — not just until it starts — so an
  event in progress keeps its spot on the homepage. "Over" is the event's end
  when set; otherwise (and for all-day events) the end of the relevant day, so a
  same-day event without an explicit end time doesn't vanish the moment it begins.
  A festival is not over before its last visible programme item ends either — the
  Kehraus runs past midnight after the last day.
  """
  def next_event(now \\ Bbh.Time.now()) do
    Repo.one(
      from e in public_top_level(),
        where:
          fragment(
            """
            GREATEST(
              CASE
                WHEN ? OR ? IS NULL
                  THEN date_trunc('day', COALESCE(?, ?)) + interval '1 day'
                ELSE ?
              END,
              (SELECT max(c."end") FROM events c WHERE c.parent_id = ? AND c.status = ANY(?))
            ) > ?
            """,
            e.all_day,
            e.ends_at,
            e.ends_at,
            e.starts_at,
            e.ends_at,
            e.id,
            ^Event.visible_child_statuses(),
            ^now
          ),
        order_by: [asc: e.starts_at],
        limit: 1,
        preload: [:location]
    )
  end

  @doc """
  The festival the dev time travel (`/dev/zeitreise`) walks through: the next public
  all-day event spanning several days that is not over yet, or else the most recent
  one — preferring festivals with a programme, so the demo seed wins over a real
  festival on the same days. Visible programme items are preloaded chronologically.
  Takes the *real* time, never the simulated one, so the target does not move while
  you travel.
  """
  def dev_festival(now \\ Bbh.Time.real_now()) do
    multi_day =
      from e in public_top_level(),
        where:
          e.all_day and not is_nil(e.ends_at) and
            fragment("?::date > ?::date", e.ends_at, e.starts_at),
        preload: [:location, children: ^visible_children()],
        limit: 1

    today = DateTime.to_date(now)

    has_programme =
      dynamic([e], fragment("EXISTS (SELECT 1 FROM events c WHERE c.parent_id = ?)", e.id))

    (Repo.one(
       from e in multi_day,
         where: fragment("?::date >= ?", e.ends_at, ^today),
         order_by: ^[desc: has_programme, asc: dynamic([e], e.starts_at)]
     ) ||
       Repo.one(
         from e in multi_day,
           order_by: ^[desc: has_programme, desc: dynamic([e], e.starts_at)]
       ))
    |> put_parent_on_children()
  end

  @doc """
  All public top-level events for a given year, chronological. Each carries
  `child_count`, the number of visible programme items.
  """
  def list_events_by_year(year) do
    counts =
      from c in Event,
        where: not is_nil(c.parent_id) and c.status in ^Event.visible_child_statuses(),
        group_by: c.parent_id,
        select: %{parent_id: c.parent_id, n: count(c.id)}

    Repo.all(
      from e in public_top_level(),
        left_join: k in subquery(counts),
        on: k.parent_id == e.id,
        where: e.year == ^year,
        order_by: [asc: e.starts_at],
        select_merge: %{child_count: coalesce(k.n, 0)},
        preload: [:location]
    )
  end

  @doc """
  A single public top-level event by slug + year, with location and its visible
  programme items (each with `parent` set, so `BbhWeb.EventPaths` can link it).
  """
  def get_public_event(slug, year) do
    Repo.one(
      from e in public_top_level(),
        where: e.slug == ^slug and e.year == ^year,
        preload: [:location, children: ^visible_children()]
    )
    |> put_parent_on_children()
  end

  @doc """
  A public top-level event by id, preloaded like `get_public_event/2` — what an event
  content block shows. `nil` for an unknown or non-public event and for a programme item.
  """
  def get_public_event_by_id(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id || "") do
      Repo.one(
        from e in public_top_level(),
          where: e.id == ^uuid,
          preload: [:location, children: ^visible_children()]
      )
      |> put_parent_on_children()
    else
      :error -> nil
    end
  end

  @doc "A visible programme item by its festival's year + slug and its own slug."
  def get_public_child(year, parent_slug, child_slug) do
    Repo.one(
      from [c, parent: p] in public_children(),
        where: p.year == ^year and p.slug == ^parent_slug and c.slug == ^child_slug,
        preload: [:location, parent: {p, :location}]
    )
  end

  @doc """
  The programme item of `parent` to highlight at `now` (the homepage's "Jetzt" /
  "Als Nächstes"): the first published one that has not ended yet, so a running item
  counts; `nil` once the programme is over. Canceled items are skipped — the
  festival page lists them, the homepage highlights what actually takes place.
  """
  def next_child(%Event{} = parent, now \\ Bbh.Time.now()),
    do: first_child(parent, dynamic([c], c.ends_at > ^now))

  @doc """
  The first published programme item of `parent` that has not started yet at `now` —
  what the homepage countdown counts down to (a running item has nothing left to
  count down to).
  """
  def next_child_to_start(%Event{} = parent, now \\ Bbh.Time.now()),
    do: first_child(parent, dynamic([c], c.starts_at > ^now))

  @doc "The first published programme item of `parent`, or `nil` without a programme."
  def first_child(%Event{} = parent), do: first_child(parent, true)

  defp first_child(%Event{id: parent_id} = parent, condition) do
    Repo.one(
      from c in visible_children(),
        where: c.parent_id == ^parent_id and c.status == "published",
        where: ^condition,
        limit: 1
    )
    |> case do
      nil -> nil
      child -> %{child | parent: parent}
    end
  end

  @doc "All public events for the iCal feed: top-level events plus visible programme items."
  def all_public_events do
    top = Repo.all(from e in public_top_level(), preload: [:location])

    items =
      Repo.all(from [c, parent: p] in public_children(), preload: [:location, parent: p])

    Enum.sort_by(top ++ items, & &1.starts_at, DateTime)
  end

  @doc "Distinct years that have public events (for the year navigation)."
  def event_years do
    Repo.all(
      from e in public_top_level(), distinct: true, select: e.year, order_by: [desc: e.year]
    )
  end

  # Public = published, publicly announced, not on an internal calendar — and not a
  # programme item, which only ever appears through its festival.
  defp public_top_level do
    from e in Event,
      where:
        is_nil(e.parent_id) and e.status == "published" and e.announce == true and
          is_nil(e.calendar)
  end

  # Visible programme items: published or canceled, under a public festival. The
  # festival is bound as `:parent`.
  defp public_children do
    from c in Event,
      join: p in assoc(c, :parent),
      as: :parent,
      where:
        c.status in ^Event.visible_child_statuses() and p.status == "published" and
          p.announce == true and is_nil(p.calendar)
  end

  # Programme items to preload under an already public festival.
  defp visible_children do
    from c in Event,
      where: c.status in ^Event.visible_child_statuses(),
      order_by: c.starts_at,
      preload: [:location]
  end

  defp put_parent_on_children(nil), do: nil

  defp put_parent_on_children(%Event{children: children} = event) do
    parent = %{event | children: []}
    %{event | children: Enum.map(children, &%{&1 | parent: parent})}
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
    from(e in Event, order_by: [desc: e.starts_at], preload: [:location, :parent])
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

  ## Admin — festivals and their programme

  @doc """
  Festivals `user` may attach a programme item to (the event form's "Gehört zu"):
  top-level, all-day, spanning several days, starting within a year of `around`,
  never `except_id` itself. `{label, id}` tuples, chronological.
  """
  def festival_options(user, around, except_id \\ nil) do
    from(e in Event,
      where:
        is_nil(e.parent_id) and e.all_day and not is_nil(e.ends_at) and
          fragment("?::date > ?::date", e.ends_at, e.starts_at) and
          e.starts_at >= ^DateTime.add(around, -366, :day) and
          e.starts_at <= ^DateTime.add(around, 366, :day),
      order_by: e.starts_at
    )
    |> scope_events(user)
    |> Repo.all()
    |> Enum.reject(&(&1.id == except_id))
    |> Enum.map(&{"#{&1.title} (#{Calendar.strftime(&1.starts_at, "%d.%m.%Y")})", &1.id})
  end

  @doc """
  Events an event content block can show: top-level, not on an internal calendar, any
  status (an invitation is often drafted before its festival is published — the block
  stays empty until then), starting from half a year before `around` on, chronological.
  Multi-day festivals sort first, since they are what the block is for. Each carries
  `child_count`, its number of programme items (any status).

  `query` filters by title (case-insensitive substring); `limit` caps the result;
  `include` is an event id kept regardless of its date (a block's current choice).
  """
  def block_event_options(around, opts \\ []) do
    counts =
      from c in Event,
        where: not is_nil(c.parent_id),
        group_by: c.parent_id,
        select: %{parent_id: c.parent_id, n: count(c.id)}

    query =
      from e in Event,
        left_join: k in subquery(counts),
        on: k.parent_id == e.id,
        where: is_nil(e.parent_id) and is_nil(e.calendar),
        where: ^recent_or_included(around, opts[:include]),
        order_by: [
          desc:
            coalesce(
              fragment("? AND ?::date > ?::date", e.all_day, e.ends_at, e.starts_at),
              false
            ),
          asc: e.starts_at
        ],
        limit: ^Keyword.get(opts, :limit, 50),
        select_merge: %{child_count: coalesce(k.n, 0)}

    query =
      case Keyword.get(opts, :query) do
        q when is_binary(q) and q != "" ->
          where(query, [e], ilike(e.title, ^"%#{escape_like(q)}%"))

        _ ->
          query
      end

    Repo.all(query)
  end

  defp recent_or_included(around, include) do
    recent = dynamic([e], e.starts_at >= ^DateTime.add(around, -183, :day))

    case Ecto.UUID.cast(include || "") do
      {:ok, id} -> dynamic([e], ^recent or e.id == ^id)
      :error -> recent
    end
  end

  defp escape_like(value), do: String.replace(value, ["\\", "%", "_"], &("\\" <> &1))

  @doc "A festival's whole programme for the admin, any status, chronological."
  def list_children(%Event{id: id}) do
    Repo.all(from c in Event, where: c.parent_id == ^id, order_by: c.starts_at)
  end

  @doc """
  Earlier festivals with a programme to copy into `festival`, latest first.
  """
  def programme_sources(%Event{id: id, starts_at: starts_at}) do
    Repo.all(
      from e in Event,
        where:
          is_nil(e.parent_id) and e.id != ^id and e.starts_at < ^starts_at and
            fragment("EXISTS (SELECT 1 FROM events c WHERE c.parent_id = ?)", e.id),
        order_by: [desc: e.starts_at],
        limit: 5
    )
  end

  @doc """
  Copy `source`'s programme into `target` as drafts, shifted by the whole days
  between the two festivals' first days (same weekdays when both start on the same
  weekday). Locations, text and times of day come along; reminders and cancellations
  do not. All or nothing: `{:ok, items}`, or `{:error, title, changeset}` for the
  first item that does not fit the new festival.
  """
  def copy_programme(%Event{} = source, %Event{} = target) do
    shift = Date.diff(DateTime.to_date(target.starts_at), DateTime.to_date(source.starts_at))

    Repo.transaction(fn ->
      source
      |> list_children()
      |> Enum.map(fn item ->
        attrs = %{
          parent_id: target.id,
          status: "draft",
          title: item.title,
          slug: item.slug,
          starts_at: DateTime.add(item.starts_at, shift, :day),
          ends_at: item.ends_at && DateTime.add(item.ends_at, shift, :day),
          body: item.body,
          location_id: item.location_id,
          enable_ical: item.enable_ical
        }

        case %Event{} |> Event.changeset(attrs) |> Repo.insert() do
          {:ok, copy} -> copy
          {:error, changeset} -> Repo.rollback({item.title, changeset})
        end
      end)
    end)
    |> case do
      {:ok, items} ->
        Bbh.Search.reindex_after({:ok, items})

      {:error, {title, changeset}} ->
        {:error, title, changeset}
    end
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
  Reminders that are due to be sent: not yet sent, whose event is still a published,
  upcoming, publicly visible event, and which have come due — either the relative
  lead time was reached (`starts_at - lead_days <= now`) or the absolute
  `scheduled_at` has passed. Programme items qualify when their festival is public
  (their own `announce`/`calendar` don't apply). Preloads the event and its parent.
  """
  def due_reminders(now \\ Bbh.Time.now()) do
    Repo.all(
      from r in EventReminder,
        join: e in assoc(r, :event),
        left_join: p in assoc(e, :parent),
        where:
          is_nil(r.sent_at) and e.status == "published" and e.starts_at > ^now and
            ((is_nil(e.parent_id) and e.announce == true and is_nil(e.calendar)) or
               (p.status == "published" and p.announce == true and is_nil(p.calendar))) and
            (fragment("? - make_interval(days => ?) <= ?", e.starts_at, r.lead_days, ^now) or
               r.scheduled_at <= ^now),
        preload: [event: {e, parent: p}]
    )
  end

  @doc "Mark a reminder as sent so it is not delivered again."
  def mark_reminder_sent(%EventReminder{} = reminder) do
    reminder
    |> Ecto.Changeset.change(sent_at: Bbh.Time.now())
    |> Repo.update()
  end

  ## Event publish notifications ("Neuer Termin" push)

  @doc """
  Public, published, still-upcoming events whose "Neuer Termin" push has not been
  sent yet. Mirrors `Content.articles_pending_notification/0`; the notifier marks
  each via `mark_event_notified/1` so it is pushed at most once. Programme items
  never get this push — only their festival does.
  """
  def events_pending_notification(now \\ Bbh.Time.now()) do
    Repo.all(
      from e in Event,
        where:
          is_nil(e.notified_at) and is_nil(e.parent_id) and e.status == "published" and
            e.announce == true and is_nil(e.calendar) and e.starts_at > ^now,
        order_by: [asc: e.starts_at]
    )
  end

  @doc "Mark an event's publish push as sent so it is not delivered again."
  def mark_event_notified(%Event{} = event) do
    event
    |> Ecto.Changeset.change(notified_at: Bbh.Time.now())
    |> Repo.update()
  end
end
