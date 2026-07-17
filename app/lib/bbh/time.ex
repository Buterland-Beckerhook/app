defmodule Bbh.Time do
  @moduledoc """
  Time-zone helpers for the club's configured zone.

  Event and article times are stored as **local wall-clock** components in
  `:utc_datetime` columns (the admin forms and templates read/write the raw
  components without conversion). `DateTime.utc_now/0`, by contrast, is real UTC —
  so seeding or comparing those fields against it is off by the zone's offset,
  which is what makes freshly-created times look shifted in the admin.

  `now/1` returns the current moment in the configured zone, re-tagged as UTC so it
  is a drop-in for `DateTime.utc_now/1`: same struct shape, castable to
  `:utc_datetime`, and directly comparable with the stored wall-clock values.
  """

  @default_time_zone "Europe/Berlin"

  @doc """
  The IANA time zone the club operates in.

  Configured via `config :bbh, :time_zone` / the `TIME_ZONE` env var; defaults to
  `#{@default_time_zone}`.
  """
  def time_zone, do: Application.get_env(:bbh, :time_zone, @default_time_zone)

  @doc """
  "Now" as local wall-clock time in the configured zone, re-tagged as UTC.

  Use this instead of `DateTime.utc_now/1` for event/article times so the value
  lines up with the wall-clock components those fields store.
  """
  def now(precision \\ :second) do
    time_zone()
    |> DateTime.now!()
    |> DateTime.to_naive()
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.truncate(precision)
  end
end
