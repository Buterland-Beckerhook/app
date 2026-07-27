defmodule Bbh.Settings.SiteSettings do
  @moduledoc """
  Singleton row of site-wide settings: the homepage notice banner and the
  push-notification quiet-hours window. There is exactly one row (seeded by the
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
end
