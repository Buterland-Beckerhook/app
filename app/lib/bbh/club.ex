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

  @doc """
  The current holder of a role — the last/currently serving person.

  Ordered by "Amt bis" (`year_end`) descending with NULLs first, so a still-serving
  person (no end year) wins, then the most recent end year; ties broken by `sort_order`
  then `name`. Returns `nil` if no one holds the role.
  """
  def role_holder(role) when is_binary(role) do
    Repo.one(
      from p in Person,
        where: p.role == ^role,
        order_by: [desc_nulls_first: p.year_end, asc: p.sort_order, asc: p.name],
        limit: 1
    )
  end

  @doc "Current board (Vorstand)."
  def list_vorstand, do: list_people(Person.vorstand_roles())

  @doc "Current officers (Offiziere)."
  def list_offiziere, do: list_people(Person.offiziere_roles())

  defp filter_honorary(query, "only"), do: where(query, [p], p.honorary_member == true)
  defp filter_honorary(query, "exclude"), do: where(query, [p], p.honorary_member == false)
  defp filter_honorary(query, _all), do: query

  ## Admin CRUD

  def list_all_people do
    Repo.all(from p in Person, order_by: [asc: p.sort_order, asc: p.name])
  end

  def count_people, do: Repo.aggregate(Person, :count, :id)
  def get_person!(id), do: Repo.get!(Person, id)
  def create_person(attrs), do: %Person{} |> Person.changeset(attrs) |> Repo.insert()
  def update_person(%Person{} = p, attrs), do: p |> Person.changeset(attrs) |> Repo.update()
  def delete_person(%Person{} = p), do: Repo.delete(p)
  def change_person(%Person{} = p, attrs \\ %{}), do: Person.changeset(p, attrs)

  @doc "Role options as {label, value} tuples for a form select."
  def role_options, do: Enum.map(Person.roles(), &{Person.role_label(&1), &1})
end
