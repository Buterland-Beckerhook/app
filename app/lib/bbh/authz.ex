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

  @doc "Whether the user may open a given admin section."
  def can_access_section?(%User{} = user, section) do
    cond do
      User.admin?(user) -> true
      section == :dashboard -> true
      section in [:events, :shares] -> user.role != "tickets"
      section in @content_sections -> user.role == "editor"
      true -> false
    end
  end

  def can_access_section?(_, _), do: false

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
    do: User.admin?(user) or User.manages_calendar?(user, calendar)

  def can_delete_event?(_, _), do: false

  @doc "Whether the user may delete a non-event resource (Artikel/Orte/Personen/Seiten)."
  def can_delete?(%User{} = user, _resource), do: User.admin?(user)
  def can_delete?(_, _), do: false

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
    do: User.admin?(user) or queues != []

  def can_access_tickets?(_), do: false

  @doc "The queues the scope sees: all for admins, else the granted ones."
  def visible_queues(%Scope{user: user, ticket_queues: queues}) do
    if User.admin?(user), do: Queue.keys(), else: queues
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
