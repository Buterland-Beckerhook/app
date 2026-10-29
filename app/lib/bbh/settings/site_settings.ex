defmodule Bbh.Settings.SiteSettings do
  @moduledoc """
  Singleton row of site-wide settings: the homepage notice banner, the
  push-notification quiet-hours window and the Postfach reminders. There is exactly one row (seeded by the
  migration); read/write it through `Bbh.Settings`.
  """
  use Bbh.Schema

  schema "site_settings" do
    field :home_notice_text, :string
    field :home_notice_enabled, :boolean, default: false

    # Quiet hours suppress push notifications overnight; the window is given in
    # whole local (Europe/Berlin) hours and may wrap past midnight (start > end).
    field :quiet_hours_enabled, :boolean, default: true
    field :quiet_hours_start, :integer, default: 22
    field :quiet_hours_end, :integer, default: 8

    # Postfach reminders (Bbh.Workers.TicketReminder) and what counts as "überfällig".
    # Retention is deliberately not here: it is stated in the Datenschutzerklärung and
    # must not change by a click (env, see deploy/.env.example).
    field :ticket_reminder_hour, :integer, default: 8
    field :ticket_remind_unassigned_hours, :integer, default: 24
    field :ticket_remind_idle_days, :integer, default: 7
    field :ticket_remind_waiting_days, :integer, default: 14
    field :ticket_escalate_days, :integer, default: 3
    field :ticket_admin_digest_enabled, :boolean, default: true
    # The local day the reminders last went out — set by the worker, not the form.
    field :ticket_reminders_sent_on, :date
    # How far the optional Junk import has read (Bbh.Workers.ImapPoller).
    field :ticket_junk_uidvalidity, :integer
    field :ticket_junk_last_uid, :integer

    timestamps()
  end

  @doc false
  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [
      :home_notice_text,
      :home_notice_enabled,
      :quiet_hours_enabled,
      :quiet_hours_start,
      :quiet_hours_end
    ])
    |> update_change(:home_notice_text, &Bbh.Html.sanitize/1)
    |> validate_inclusion(:quiet_hours_start, 0..23,
      message: "muss eine Stunde zwischen 0 und 23 sein"
    )
    |> validate_inclusion(:quiet_hours_end, 0..23,
      message: "muss eine Stunde zwischen 0 und 23 sein"
    )
  end

  @doc "Changeset for the Postfach tab: reminder hour, thresholds and the admin digest."
  def tickets_changeset(settings, attrs) do
    settings
    |> cast(attrs, [
      :ticket_reminder_hour,
      :ticket_remind_unassigned_hours,
      :ticket_remind_idle_days,
      :ticket_remind_waiting_days,
      :ticket_escalate_days,
      :ticket_admin_digest_enabled
    ])
    |> validate_required([
      :ticket_reminder_hour,
      :ticket_remind_unassigned_hours,
      :ticket_remind_idle_days,
      :ticket_remind_waiting_days,
      :ticket_escalate_days
    ])
    |> validate_number(:ticket_reminder_hour,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 23
    )
    |> validate_number(:ticket_remind_unassigned_hours,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 168
    )
    |> validate_number(:ticket_remind_idle_days,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 90
    )
    |> validate_number(:ticket_remind_waiting_days,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 90
    )
    |> validate_number(:ticket_escalate_days,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 90
    )
  end
end
