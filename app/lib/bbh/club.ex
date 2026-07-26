defmodule Bbh.Club do
  @moduledoc "Read/query API for people (board, officers, historical figures)."
  import Ecto.Query
  alias Bbh.Repo
  alias Bbh.Club.Person

  @doc """
  People holding any of the given roles, sorted. An **empty** role list means every role.

  Options:

    * `:honorary` — `"all"` (default), `"only"` or `"exclude"`
    * `:only_active` — when true, drop everyone whose „Amt bis" is set
  """
  def list_people(roles, opts \\ []) when is_list(roles) do
    from(p in Person, order_by: [asc: p.sort_order, asc: p.name])
    |> filter_roles(roles)
    |> filter_honorary(Keyword.get(opts, :honorary, "all"))
    |> filter_active(Keyword.get(opts, :only_active, false))
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

  # The block editor's legend promises „Rollen (leer = alle)", but `p.role in ^[]` matches
  # nobody — an unfiltered block used to render an empty list.
  defp filter_roles(query, []), do: query
  defp filter_roles(query, roles), do: where(query, [p], p.role in ^roles)

  defp filter_honorary(query, "only"), do: where(query, [p], p.honorary_member == true)
  defp filter_honorary(query, "exclude"), do: where(query, [p], p.honorary_member == false)
  defp filter_honorary(query, _all), do: query

  # An empty „Amt bis" is the only signal the data carries for "still serving" — the same
  # one `role_holder/1` orders by. `death_date` is free text and cannot be compared.
  #
  # No catch-all clause on purpose, unlike `filter_honorary/2` above: that one degrades to
  # its documented widest default, while silently ignoring a truthy-but-not-`true` flag here
  # would quietly publish people a page asked to hide. Better to raise at the call site.
  defp filter_active(query, true), do: where(query, [p], is_nil(p.year_end))
  defp filter_active(query, flag) when flag in [nil, false], do: query

  ## Admin CRUD

  def list_all_people do
    Repo.all(from p in Person, order_by: [asc: p.sort_order, asc: p.name])
  end

  def count_people, do: Repo.aggregate(Person, :count, :id)
  # The portrait rides along so the admin form can show the chosen picture.
  def get_person!(id), do: Person |> Repo.get!(id) |> Repo.preload(:portrait)
  def create_person(attrs), do: %Person{} |> Person.changeset(attrs) |> Repo.insert()
  def update_person(%Person{} = p, attrs), do: p |> Person.changeset(attrs) |> Repo.update()
  def delete_person(%Person{} = p), do: Repo.delete(p)
  def change_person(%Person{} = p, attrs \\ %{}), do: Person.changeset(p, attrs)

  @doc "Role options as {label, value} tuples for a form select."
  def role_options, do: Enum.map(Person.roles(), &{Person.role_label(&1), &1})
end
