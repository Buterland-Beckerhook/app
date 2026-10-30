defmodule Bbh.Calendar.Locations do
  @moduledoc "Event venues: admin CRUD and form options. A new venue may grow the map."
  import Ecto.Query
  alias Bbh.Repo
  alias Bbh.Calendar.Location

  def list_locations, do: Repo.all(from l in Location, order_by: l.name)
  def get_location!(id), do: Repo.get!(Location, id)

  def create_location(attrs),
    do: %Location{} |> Location.changeset(attrs) |> Repo.insert() |> tap(&grow_map/1)

  def update_location(%Location{} = loc, attrs),
    do: loc |> Location.changeset(attrs) |> Repo.update() |> tap(&grow_map/1)

  # A venue outside the map archive's area triggers a re-extract (Bbh.Map).
  defp grow_map({:ok, location}), do: Bbh.Map.location_changed(location)
  defp grow_map(_error), do: :ok

  def delete_location(%Location{} = loc), do: Repo.delete(loc)
  def change_location(%Location{} = loc, attrs \\ %{}), do: Location.changeset(loc, attrs)

  @doc "Locations as {name, id} tuples for a form select."
  def location_options do
    Repo.all(from l in Location, order_by: l.name, select: {l.name, l.id})
  end
end
