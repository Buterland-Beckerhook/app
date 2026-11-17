defmodule Bbh.Authz do
  @moduledoc """
  Central authorization policy for the admin area.

  Roles:
    * `admin` — full access to every section, every calendar, every delete.
    * `editor` — all content sections; may manage **public** events plus any non-public
      calendars explicitly granted via `user.calendars`.
    * `calendar_editor` — only the Termine section, limited to the calendars granted via
      `user.calendars`.
    * `tickets` ("Nur Postfach") — no content, no Termine; only the Postfach queues
      granted to them.
    * `none` ("Kein Zugriff") — nothing at all, not even granted queues or calendars:
      for people who keep their account after leaving an office. They see only a
      notice on the dashboard (`no_access?/1`).

  The Postfach is independent of the role: anyone with a queue grant
  (`Bbh.Tickets.Grants`, carried on the scope as `ticket_queues`) works those queues,
  admins read all of them. Its checks therefore take the scope, not the user.

  Deletes are admin-only everywhere, except events on a non-public calendar, which the
  users granted that calendar may also delete.

  Session strength: every section but Termine requires a strongly authenticated session
  (enforced by the `BbhWeb.UserAuth` on_mount hooks); inside Termine, the public calendar
  does too (`can_manage_calendar?/2`).
  """
  alias Bbh.Accounts.{Scope, User}
  alias Bbh.Calendar.Event
  alias Bbh.Tickets.Queue

  @content_sections ~w(articles tags locations people trophies pages media)a

  @doc "Whether the (possibly nil, e.g. anonymous) scope belongs to an admin."
  def admin?(%Scope{user: user}), do: User.admin?(user)
  def admin?(_), do: false

  @doc """
  Whether the scope may do what the admin-only areas allow outside of a LiveView
  (e.g. the push device controllers): an admin with a strongly authenticated session,
  the same bar `BbhWeb.UserAuth`'s `:require_admin` hook sets.
  """
  def strong_admin?(%Scope{user: user}), do: User.admin?(user) and User.strong_auth?(user)
  def strong_admin?(_), do: false

  @doc "Whether the user may open a given admin section."
  def can_access_section?(%User{} = user, section) do
    cond do
      User.admin?(user) -> true
      section == :dashboard -> true
      section in [:events, :shares] -> user.role not in ["tickets", "none"]
      section in @content_sections -> user.role == "editor"
      true -> false
    end
  end

  def can_access_section?(_, _), do: false

  @doc """
  Whether the scope has nothing to work on in the admin area: the role "none", or a
  role whose only access comes from grants that are all empty ("Nur Postfach" without
  queues, "Kalender" without calendars and queues). The dashboard then shows a notice
  instead of its widgets, and the nav drops „Übersicht".
  """
  def no_access?(%Scope{user: %User{role: role} = user, ticket_queues: queues}) do
    case role do
      "admin" -> false
      "editor" -> false
      "tickets" -> queues == []
      "calendar_editor" -> (user.calendars || []) == [] and queues == []
      _ -> true
    end
  end

  def no_access?(_), do: true

  @doc """
  Whether this (possibly nil) scope may preview unpublished content of a section.
  Nil-safe: an anonymous scope (nil) or non-editor returns false.
  """
  def can_preview?(scope, section), do: can_access_section?(scope && scope.user, section)

  @doc """
  Whether the user may create/edit an event on the given calendar (nil = public).

  The public calendar is website content, so like the content sections it needs a
  strongly authenticated session; the internal calendars are fine with a plain one.
  """
  def can_manage_calendar?(%User{} = user, calendar) do
    cond do
      user.role == "none" -> false
      is_nil(calendar) -> (User.admin?(user) or user.role == "editor") and User.strong_auth?(user)
      User.admin?(user) -> true
      true -> User.manages_calendar?(user, calendar)
    end
  end

  def can_manage_calendar?(_, _), do: false

  @doc "Whether the user may edit this event."
  def can_edit_event?(user, %Event{calendar: calendar}), do: can_manage_calendar?(user, calendar)

  @doc "Whether the user may delete this event (admins, or grantees of a non-public calendar)."
  def can_delete_event?(%User{} = user, %Event{calendar: nil}),
    do: User.admin?(user) and User.strong_auth?(user)

  def can_delete_event?(%User{} = user, %Event{calendar: calendar}),
    do: User.admin?(user) or can_manage_calendar?(user, calendar)

  def can_delete_event?(_, _), do: false

  @doc "Whether the user may delete a non-event resource (Artikel/Orte/Personen/Seiten)."
  def can_delete?(%User{} = user, _resource), do: User.admin?(user)
  def can_delete?(_, _), do: false

  @doc """
  `can_access_section?/2` for a scope, as the contexts' create and update functions
  check it: `:ok`, or `{:error, :unauthorized}`. Nil-safe.
  """
  def authorize_section(scope, section),
    do: ok_if(can_access_section?(scope && scope.user, section))

  @doc "`can_manage_calendar?/2` for a scope (`nil` calendar = public). Nil-safe."
  def authorize_calendar(scope, calendar),
    do: ok_if(can_manage_calendar?(scope && scope.user, calendar))

  @doc "`can_delete_event?/2` for a scope. Nil-safe."
  def authorize_event_delete(scope, event),
    do: ok_if(can_delete_event?(scope && scope.user, event))

  defp ok_if(true), do: :ok
  defp ok_if(false), do: {:error, :unauthorized}

  @doc """
  `can_delete?/2` for a scope, as the contexts' delete functions check it: `:ok`, or
  `{:error, :unauthorized}`. Nil-safe.
  """
  def authorize_delete(scope, resource) do
    if can_delete?(scope && scope.user, resource), do: :ok, else: {:error, :unauthorized}
  end

  ## Postfach

  @doc "Whether the scope may open the Postfach: admins, and anyone with a queue grant."
  def can_access_tickets?(%Scope{user: user, ticket_queues: queues}),
    do: User.admin?(user) or (user.role != "none" and queues != [])

  def can_access_tickets?(_), do: false

  @doc "The queues the scope sees, in queue order: all for admins, else the granted ones."
  def visible_queues(%Scope{user: user, ticket_queues: queues}) do
    cond do
      User.admin?(user) -> Queue.keys()
      user.role == "none" -> []
      true -> Enum.filter(Queue.keys(), &(&1 in queues))
    end
  end

  def visible_queues(_), do: []

  @doc """
  Whether the scope may read and work a ticket (take it, reply, note, change its status).
  Admins may always — they are the shadow reader and can step in.
  """
  def can_view_ticket?(scope, %{queue: queue}), do: queue in visible_queues(scope)
  def can_view_ticket?(_, _), do: false

  @doc "Same as `can_view_ticket?/2`; separate so the two can diverge later."
  def can_handle_ticket?(scope, ticket), do: can_view_ticket?(scope, ticket)

  @doc "Deleting and restoring tickets is admin-only."
  def can_delete_ticket?(%Scope{user: user}), do: User.admin?(user)
  def can_delete_ticket?(_), do: false

  @doc "`{label, value}` calendar options the user may assign in the event form."
  def assignable_calendar_options(%User{} = user) do
    public = if can_manage_calendar?(user, nil), do: [{"Öffentlich", ""}], else: []

    named =
      for c <- Event.calendars(), can_manage_calendar?(user, c), do: {Event.calendar_label(c), c}

    public ++ named
  end
end
