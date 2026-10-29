defmodule Bbh.Tickets.Reminders do
  @moduledoc """
  What counts as "überfällig" in the Postfach — one definition for the list's
  "Überfällig" tab, the daily reminders and the admin digest. Thresholds come from the
  site settings (tab "Postfach"):

    * `new` and unassigned for more than `ticket_remind_unassigned_hours` → the queue
    * `open` without activity for `ticket_remind_idle_days` → the assignee
    * `follow_up` with its date reached → the assignee
    * `waiting` for `ticket_remind_waiting_days` → the assignee ("nachfassen oder schließen")

  A reminder that names the assignee goes to the queue while nobody has the ticket.
  Escalation (admin digest only): `new` and unassigned for `ticket_escalate_days`.
  """
  import Ecto.Query

  alias Bbh.Repo
  alias Bbh.Settings.SiteSettings
  alias Bbh.Tickets.{Grants, Ticket}

  @doc "Narrows a ticket query to the overdue tickets."
  def overdue(query, %SiteSettings{} = s, now \\ DateTime.utc_now(:second)) do
    %{unassigned: unassigned, idle: idle, waiting: waiting, today: today} = cutoffs(s, now)

    where(
      query,
      [t],
      is_nil(t.deleted_at) and
        ((t.status == "new" and is_nil(t.assignee_id) and t.inserted_at < ^unassigned) or
           (t.status == "open" and t.last_activity_at < ^idle) or
           (t.status == "follow_up" and t.follow_up_on <= ^today) or
           (t.status == "waiting" and t.last_activity_at < ^waiting))
    )
  end

  @doc """
  Today's reminders: `%{user_id => [{ticket, reason}]}`, one entry per user who gets a
  mail. `reason` is a German line without personal data.
  """
  def due(%SiteSettings{} = s, now \\ DateTime.utc_now(:second)) do
    Ticket
    |> overdue(s, now)
    |> order_by([t], asc: t.number)
    |> Repo.all()
    |> Enum.flat_map(fn ticket ->
      reason = reason(ticket, s, now)
      for user_id <- recipients(ticket), do: {user_id, {ticket, reason}}
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  @doc "New tickets nobody has taken for `ticket_escalate_days` — for the admin digest."
  def escalations(%SiteSettings{} = s, now \\ DateTime.utc_now(:second)) do
    cutoff = DateTime.add(now, -s.ticket_escalate_days, :day)

    Repo.all(
      from t in Ticket,
        where:
          is_nil(t.deleted_at) and t.status == "new" and is_nil(t.assignee_id) and
            t.inserted_at < ^cutoff,
        order_by: t.number
    )
  end

  defp recipients(%Ticket{status: "new", queue: queue}), do: queue_users(queue)
  defp recipients(%Ticket{assignee_id: nil, queue: queue}), do: queue_users(queue)
  defp recipients(%Ticket{assignee_id: id}), do: [id]

  defp queue_users(queue), do: queue |> Grants.list_users() |> Enum.map(& &1.id)

  @doc false
  def reason(%Ticket{status: "new"}, s, _now),
    do: "seit über #{s.ticket_remind_unassigned_hours} Std. niemandem zugewiesen"

  def reason(%Ticket{status: "follow_up", follow_up_on: date}, _s, _now),
    do: "Wiedervorlage fällig (#{Calendar.strftime(date, "%d.%m.%Y")})"

  def reason(%Ticket{status: "waiting", last_activity_at: at}, _s, now),
    do:
      "wartet seit #{DateTime.diff(now, at, :day)} Tagen auf Antwort – nachfassen oder schließen"

  def reason(%Ticket{last_activity_at: at}, _s, now),
    do: "seit #{DateTime.diff(now, at, :day)} Tagen nicht bearbeitet"

  defp cutoffs(s, now) do
    %{
      unassigned: DateTime.add(now, -s.ticket_remind_unassigned_hours, :hour),
      idle: DateTime.add(now, -s.ticket_remind_idle_days, :day),
      waiting: DateTime.add(now, -s.ticket_remind_waiting_days, :day),
      # The club's calendar day, not UTC's.
      today: now |> DateTime.shift_zone!(Bbh.Time.time_zone()) |> DateTime.to_date()
    }
  end
end
