defmodule BbhWeb.Authz do
  @moduledoc """
  Central authorization policy for the admin area.

  Roles:
    * `admin` — full access to every section, every calendar, every delete.
    * `editor` — all content sections; may manage **public** events plus any non-public
      calendars explicitly granted via `user.calendars`.
    * `calendar_editor` — only the Termine section, limited to the calendars granted via
      `user.calendars`.

  Deletes are admin-only everywhere, except events on a non-public calendar, which the
  users granted that calendar may also delete.
  """
  alias Bbh.Accounts.User
  alias Bbh.Calendar.Event

  @content_sections ~w(articles locations people pages media)a

  @doc "Whether the user may open a given admin section."
  def can_access_section?(%User{} = user, section) do
    cond do
      User.admin?(user) -> true
      section in [:dashboard, :events] -> true
      section in @content_sections -> user.role == "editor"
      true -> false
    end
  end

  def can_access_section?(_, _), do: false

  @doc "Whether the user may create/edit an event on the given calendar (nil = public)."
  def can_manage_calendar?(%User{} = user, calendar) do
    cond do
      User.admin?(user) -> true
      is_nil(calendar) -> user.role == "editor"
      true -> User.manages_calendar?(user, calendar)
    end
  end

  def can_manage_calendar?(_, _), do: false

  @doc "Whether the user may edit this event."
  def can_edit_event?(user, %Event{calendar: calendar}), do: can_manage_calendar?(user, calendar)

  @doc "Whether the user may delete this event (admins, or grantees of a non-public calendar)."
  def can_delete_event?(%User{} = user, %Event{calendar: calendar}) do
    User.admin?(user) or (not is_nil(calendar) and User.manages_calendar?(user, calendar))
  end

  def can_delete_event?(_, _), do: false

  @doc "Whether the user may delete a non-event resource (Artikel/Orte/Personen/Seiten)."
  def can_delete?(%User{} = user, _resource), do: User.admin?(user)
  def can_delete?(_, _), do: false

  @doc "`{label, value}` calendar options the user may assign in the event form."
  def assignable_calendar_options(%User{} = user) do
    public = if can_manage_calendar?(user, nil), do: [{"Öffentlich", ""}], else: []

    named =
      for c <- Event.calendars(), can_manage_calendar?(user, c), do: {Event.calendar_label(c), c}

    public ++ named
  end
end
