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

  In dev (`config :bbh, :dev_clock, true`) `now/1` can be shifted per process for
  time travel — see `BbhWeb.Plugs.DevClock`. Elsewhere that branch is not compiled in.
  """

  @default_time_zone "Europe/Berlin"
  @dev_clock Application.compile_env(:bbh, :dev_clock, false)
  @offset_key :bbh_clock_offset

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
    precision
    |> real_now()
    |> apply_offset(offset())
  end

  @doc """
  Like `now/1`, but never shifted by the dev clock — for the dev clock itself, which
  has to measure its offset against the real time.
  """
  def real_now(precision \\ :second) do
    time_zone()
    |> DateTime.now!()
    |> DateTime.to_naive()
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.truncate(precision)
  end

  @doc "Shifts `dt` by `seconds`. The dev clock's arithmetic, exposed for tests."
  def apply_offset(%DateTime{} = dt, 0), do: dt
  def apply_offset(%DateTime{} = dt, seconds), do: DateTime.add(dt, seconds, :second)

  @doc "The process-dictionary key the dev clock stores its offset (in seconds) under."
  def offset_key, do: @offset_key

  if @dev_clock do
    defp offset, do: Process.get(@offset_key, 0)
  else
    defp offset, do: 0
  end
end
