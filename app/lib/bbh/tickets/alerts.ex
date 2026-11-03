defmodule Bbh.Tickets.Alerts do
  @moduledoc """
  When and how staff hear about the Postfach, per user.

  New requests and replies go into an outbox (`Bbh.Tickets.Notification`).
  `Bbh.Workers.TicketNewNotifier` flushes it every two minutes. The default sends at each
  run; any other interval means fixed times, counted from the end of the site-wide quiet
  hours (`slots/2`): with quiet hours 22–8, "every 4 hours" is 8, 12, 16 and 20 o'clock,
  and "once a day" is 19 o'clock, the evening being when a volunteer has time for it.
  Whatever arrived before a time goes out then, in one message, together with the day's
  reminders (`Bbh.Tickets.Reminders`), at most once a day. Whether something still
  matters is decided when it is sent: a request someone took meanwhile, or one moved to
  another queue, is dropped.

  During quiet hours nothing goes out. The channel is `mail`, `push` or `both`. Someone
  on `push` whose devices are all gone or failing gets the mail instead, so nothing is
  lost.

  Like the mails (`Bbh.Tickets.Notifier`), pushes name queue and reference, nothing else.
  """
  import Ecto.Query

  alias Bbh.Accounts.User
  alias Bbh.Notifications
  alias Bbh.Repo
  alias Bbh.Settings
  alias Bbh.Settings.SiteSettings
  alias Bbh.Tickets.{Grants, Notification, Notifier, Queue, Reminders, Ticket}

  # An interval this short is every run of the worker.
  @immediate_minutes 2
  @daily_minutes 1440
  # "Once a day": in the evening, or the last active hour if that is quiet.
  @daily_slot 19 * 60

  @doc "A changeset for the user's notification settings."
  def change_preferences(%User{} = user, attrs \\ %{}),
    do: User.ticket_notifications_changeset(user, attrs)

  @doc "Saves the user's notification settings."
  def update_preferences(%User{} = user, attrs),
    do: user |> change_preferences(attrs) |> Repo.update()

  @doc "Queues the announcement of new tickets for everyone who works their queues."
  def enqueue_new(tickets) do
    tickets
    |> Enum.flat_map(fn ticket ->
      for user <- Grants.notify_users(ticket.queue), do: row(user.id, ticket.id, "new")
    end)
    |> insert_rows()
  end

  @doc "Queues the announcement of a reply: to the assignee, or else the queue."
  def enqueue_reply(%Ticket{} = ticket, users) do
    users |> Enum.map(&row(&1.id, ticket.id, "reply")) |> insert_rows()
  end

  defp row(user_id, ticket_id, kind) do
    %{
      id: Ecto.UUID.generate(),
      user_id: user_id,
      ticket_id: ticket_id,
      kind: kind,
      inserted_at: DateTime.utc_now(:second)
    }
  end

  defp insert_rows(rows) do
    Repo.insert_all(Notification, rows,
      on_conflict: :nothing,
      conflict_target: [:user_id, :ticket_id, :kind]
    )

    :ok
  end

  @doc """
  The local times an interval sends at, as minutes of the day in ascending order, or
  `:always` for every run of the worker.
  """
  def slots(minutes, %SiteSettings{}) when minutes <= @immediate_minutes, do: :always

  def slots(@daily_minutes, %SiteSettings{} = settings) do
    {start, length} = active_window(settings)

    if rem(@daily_slot - start + @daily_minutes, @daily_minutes) < length,
      do: [@daily_slot],
      else: [rem(start + length - 60, @daily_minutes)]
  end

  def slots(minutes, %SiteSettings{} = settings) do
    {start, length} = active_window(settings)

    Enum.sort(for offset <- 0..(length - 1)//minutes, do: rem(start + offset, @daily_minutes))
  end

  # `{first minute, length in minutes}` of the part of the day outside quiet hours.
  defp active_window(%SiteSettings{
         quiet_hours_enabled: true,
         quiet_hours_start: start,
         quiet_hours_end: fin
       })
       when start != fin,
       do: {fin * 60, rem(start - fin + 24, 24) * 60}

  defp active_window(_settings), do: {8 * 60, @daily_minutes}

  @doc """
  Sends what is due. `now` is local wall-clock, see `Bbh.Time`. Nothing during quiet
  hours; a later run picks it up.
  """
  def flush(now \\ Bbh.Time.real_now()) do
    if not Settings.quiet_now?(now) do
      settings = Settings.get()
      rows = Repo.all(from n in Notification, preload: [:user, :ticket])
      reminders = todays_reminders(settings, now)

      users =
        Repo.all(from u in User, where: u.id in ^Map.keys(reminders))
        |> Kernel.++(Enum.map(rows, & &1.user))
        |> Enum.uniq_by(& &1.id)

      recipients =
        rows
        |> Enum.map(& &1.ticket.queue)
        |> Enum.uniq()
        |> Map.new(fn queue -> {queue, Enum.map(Grants.notify_users(queue), & &1.id)} end)

      by_user = Enum.group_by(rows, & &1.user_id)

      for user <- users do
        slot = latest_slot(now, slots(user.ticket_notify_interval_minutes, settings))
        user_rows = Enum.filter(Map.get(by_user, user.id, []), &arrived_by?(&1, slot))
        items = reminder_items(user, Map.get(reminders, user.id, []), slot, settings, now)
        flush_user(user, user_rows, items, recipients)
      end
    end

    :ok
  end

  defp todays_reminders(%SiteSettings{ticket_reminder_hour: hour}, %{hour: now}) when now < hour,
    do: %{}

  defp todays_reminders(settings, _now), do: Reminders.due(settings)

  defp latest_slot(now, :always), do: now

  defp latest_slot(now, slots) do
    today = DateTime.to_date(now)

    for(date <- [Date.add(today, -1), today], minute <- slots, do: at(date, minute))
    |> Enum.filter(&(DateTime.compare(&1, now) != :gt))
    |> Enum.max(DateTime)
  end

  defp at(date, minute) do
    DateTime.new!(date, Time.new!(div(minute, 60), rem(minute, 60), 0), "Etc/UTC")
  end

  defp arrived_by?(%{inserted_at: inserted_at}, slot) do
    local =
      inserted_at
      |> DateTime.shift_zone!(Bbh.Time.time_zone())
      |> DateTime.to_naive()
      |> DateTime.from_naive!("Etc/UTC")

    DateTime.compare(local, slot) != :gt
  end

  # The day's reminders travel with the user's first time at or after the reminder hour.
  defp reminder_items(_user, [], _slot, _settings, _now), do: []

  defp reminder_items(user, items, slot, settings, now) do
    today = DateTime.to_date(now)
    reminder_time = at(today, settings.ticket_reminder_hour * 60)

    if DateTime.compare(slot, reminder_time) != :lt and claim_reminders(user, today),
      do: items,
      else: []
  end

  # One conditional UPDATE, so two overlapping runs cannot both remind.
  defp claim_reminders(user, today) do
    {count, _} =
      Repo.update_all(
        from(u in User,
          where:
            u.id == ^user.id and
              (is_nil(u.ticket_reminded_on) or u.ticket_reminded_on < ^today)
        ),
        set: [ticket_reminded_on: today]
      )

    count > 0
  end

  defp flush_user(user, rows, items, recipients) do
    relevant = Enum.filter(rows, &relevant?(&1, user, recipients))

    # Delete first: a crash mid-way must not announce the same ticket twice. Whoever
    # deleted nothing lost a race with an overlapping run and leaves these to the winner.
    {deleted, _} =
      Repo.delete_all(from n in Notification, where: n.id in ^Enum.map(rows, & &1.id))

    new = if deleted > 0, do: tickets_of(relevant, "new"), else: []
    new_ids = MapSet.new(new, & &1.id)

    replies =
      if(deleted > 0, do: tickets_of(relevant, "reply"), else: [])
      |> Enum.reject(&(&1.id in new_ids))

    items = Enum.reject(items, fn {ticket, _reason} -> ticket.id in new_ids end)

    if new != [] or replies != [] or items != [] do
      deliver(
        user,
        fn -> Notifier.collected(user, new, replies, items) end,
        payload(new, replies, items)
      )
    end

    :ok
  end

  defp tickets_of(rows, kind) do
    rows
    |> Enum.filter(&(&1.kind == kind))
    |> Enum.map(& &1.ticket)
    |> Enum.sort_by(& &1.number)
  end

  defp relevant?(%{kind: "new", ticket: ticket}, user, recipients) do
    ticket.status == "new" and is_nil(ticket.deleted_at) and
      user.id in Map.get(recipients, ticket.queue, [])
  end

  defp relevant?(%{kind: "reply", ticket: ticket}, user, recipients) do
    is_nil(ticket.deleted_at) and ticket.status != "spam" and
      if(ticket.assignee_id,
        do: ticket.assignee_id == user.id,
        else: user.id in Map.get(recipients, ticket.queue, [])
      )
  end

  @doc "Someone else assigned the user a ticket. Not collected: this one is personal."
  def assigned(%User{} = user, %Ticket{} = ticket, %User{} = by) do
    deliver(user, fn -> Notifier.assigned(user, ticket, by) end, %{
      title: "Postfach",
      body: "#{Ticket.reference(ticket)} wurde dir zugewiesen",
      url: ticket_url(ticket)
    })
  end

  @doc "A trial push to all of the user's devices. Returns how many took it."
  def test_push(%User{} = user) do
    Notifications.notify_user(user, %{
      title: "Postfach",
      body: "Testnachricht: Benachrichtigungen kommen auf diesem Gerät an.",
      url: postfach_url()
    })
  end

  defp deliver(%User{ticket_notify_channel: "mail"}, mail, _payload), do: mail.()

  defp deliver(%User{ticket_notify_channel: "both"} = user, mail, payload) do
    Notifications.notify_user(user, payload)
    mail.()
  end

  defp deliver(%User{} = user, mail, payload) do
    if Notifications.notify_user(user, payload) == 0, do: mail.()
    :ok
  end

  defp payload([ticket], [], []) do
    %{
      title: "Postfach",
      body: "Neue Anfrage (#{Queue.label(ticket.queue)}): #{Ticket.reference(ticket)}",
      url: ticket_url(ticket)
    }
  end

  defp payload([], [ticket], []) do
    %{
      title: "Postfach",
      body: "Neue Antwort zu #{Ticket.reference(ticket)}",
      url: ticket_url(ticket)
    }
  end

  defp payload(new, replies, items) do
    parts = [
      count(length(new), "neue Anfrage", "neue Anfragen"),
      count(length(replies), "neue Antwort", "neue Antworten"),
      count(length(items), "wartende Anfrage", "wartende Anfragen")
    ]

    %{
      title: "Postfach",
      body: parts |> Enum.reject(&is_nil/1) |> Enum.join(", "),
      url: postfach_url()
    }
  end

  defp count(0, _one, _many), do: nil
  defp count(1, one, _many), do: "1 #{one}"
  defp count(n, _one, many), do: "#{n} #{many}"

  defp ticket_url(ticket), do: "#{postfach_url()}/#{Ticket.reference(ticket)}"
  defp postfach_url, do: "#{Bbh.Site.url()}/admin/postfach"
end
