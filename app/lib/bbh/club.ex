defmodule Bbh.Club do
  @moduledoc "Read/query API for people (board, officers, historical figures)."
  import Ecto.Query
  alias Bbh.Repo
  alias Bbh.Club.Person

  @doc "People holding any of the given roles, sorted, optionally filtered by honorary status."
  def list_people(roles, honorary \\ "all") when is_list(roles) do
    from(p in Person, where: p.role in ^roles, order_by: [asc: p.sort_order, asc: p.name])
    |> filter_honorary(honorary)
    |> preload(:portrait)
    |> Repo.all()
  end

  @doc "Current board (Vorstand)."
  def list_vorstand, do: list_people(Person.vorstand_roles())

  @doc "Current officers (Offiziere)."
  def list_offiziere, do: list_people(Person.offiziere_roles())

  defp filter_honorary(query, "only"), do: where(query, [p], p.honorary_member == true)
  defp filter_honorary(query, "exclude"), do: where(query, [p], p.honorary_member == false)
  defp filter_honorary(query, _all), do: query
end
