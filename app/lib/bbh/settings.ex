defmodule Bbh.Settings do
  @moduledoc """
  Read/write API for the site-wide settings singleton (`SiteSettings`).

  Holds the homepage notice banner and the push quiet-hours window. The row is
  seeded by the migration, so `get/0` normally returns it; if it is ever missing
  it falls back to a struct carrying the schema defaults so callers never crash.
  """
  import Ecto.Query
  alias Bbh.Repo
  alias Bbh.Settings.SiteSettings

  @doc "The settings singleton (schema defaults if no row exists yet)."
  def get do
    Repo.one(from s in SiteSettings, limit: 1) || %SiteSettings{}
  end

  @doc "A changeset for the settings form."
  def change(%SiteSettings{} = settings, attrs \\ %{}),
    do: SiteSettings.changeset(settings, attrs)

  @doc "Update (or insert, if somehow missing) the settings singleton."
  def update(attrs) do
    (Repo.one(from s in SiteSettings, limit: 1) || %SiteSettings{})
    |> SiteSettings.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @doc """
  Whether push notifications should currently be held back for quiet hours.

  `now` is local wall-clock (see `Bbh.Time.now/0`), so its hour is the local hour.
  A window with `start > end` wraps past midnight (e.g. 22 → 8).
  """
  def quiet_now?(now \\ Bbh.Time.now()) do
    quiet?(get(), now.hour)
  end

  defp quiet?(%SiteSettings{quiet_hours_enabled: false}, _hour), do: false

  defp quiet?(%SiteSettings{quiet_hours_start: start, quiet_hours_end: fin}, hour) do
    cond do
      # Degenerate/empty window — never quiet.
      start == fin -> false
      start < fin -> hour >= start and hour < fin
      # Window wraps past midnight (e.g. 22 → 8).
      true -> hour >= start or hour < fin
    end
  end
end
