defmodule Bbh.Club do
  @moduledoc "Read/query API for people (board, officers, historical figures) and Pokale."
  import Ecto.Query
  alias Bbh.{Authz, Repo}
  alias Bbh.Club.Person
  alias Bbh.Club.Trophy
  alias Bbh.Club.TrophyWin

  @doc """
  People holding any of the given roles, sorted. An **empty** role list means every role.

  Options:

    * `:honorary` — `"all"` (default), `"only"` or `"exclude"`
    * `:alive` — `"all"` (default), `"living"` or `"deceased"` (by `death_date`)
    * `:only_active` — when true, drop everyone who is no longer active: „Amt bis" set
      or deceased (see `Bbh.Club.Person.active?/1`)
    * `:sort` — `"sort_order"` (default), `"year_start"` (Amtsantritt, oldest first) or
      `"honorary_since"` (Ernennung zum Ehrenmitglied, oldest first)
  """
  def list_people(roles, opts \\ []) when is_list(roles) do
    from(p in Person)
    |> filter_roles(roles)
    |> filter_honorary(Keyword.get(opts, :honorary, "all"))
    |> filter_alive(Keyword.get(opts, :alive, "all"))
    |> filter_active(Keyword.get(opts, :only_active, false))
    |> order_people(Keyword.get(opts, :sort, "sort_order"))
    |> preload(:portrait)
    |> Repo.all()
  end

  # „Amt (from)" = Amtsantritts-Jahr (`year_start`), oldest first; people without one sort
  # last, then the manual `sort_order`, then `name`. Any other value keeps the default order.
  defp order_people(query, "year_start"),
    do: order_by(query, [p], asc_nulls_last: p.year_start, asc: p.sort_order, asc: p.name)

  # The unknown-year placeholder (1900) sorts first; those appointments predate the
  # known ones anyway.
  defp order_people(query, "honorary_since"),
    do: order_by(query, [p], asc_nulls_last: p.honorary_since, asc: p.sort_order, asc: p.name)

  defp order_people(query, _),
    do: order_by(query, [p], asc: p.sort_order, asc: p.name)

  @doc """
  The current holder of a role — the last/currently serving person.

  An active person (no „Amt bis", not deceased) wins; otherwise the most recent
  „Amt bis" — a deceased holder without one counts as the latest. Ties broken by
  `sort_order` then `name`. Returns `nil` if no one holds the role.
  """
  def role_holder(role) when is_binary(role) do
    Repo.one(
      from p in Person,
        where: p.role == ^role,
        order_by: [
          desc: is_nil(p.year_end) and is_nil(p.death_date),
          desc_nulls_first: p.year_end,
          asc: p.sort_order,
          asc: p.name
        ],
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

  defp filter_honorary(query, "only"), do: where(query, [p], not is_nil(p.honorary_since))
  defp filter_honorary(query, "exclude"), do: where(query, [p], is_nil(p.honorary_since))
  defp filter_honorary(query, _all), do: query

  defp filter_alive(query, "living"), do: where(query, [p], is_nil(p.death_date))
  defp filter_alive(query, "deceased"), do: where(query, [p], not is_nil(p.death_date))
  defp filter_alive(query, _all), do: query

  # Active = no „Amt bis" and not deceased (`Person.active?/1`, the same rule
  # `role_holder/1` orders by). Nobody enters an „Amt bis" for someone who died in office,
  # so the death date has to end the office too.
  #
  # No catch-all clause on purpose, unlike `filter_honorary/2` above: that one degrades to
  # its documented widest default, while silently ignoring a truthy-but-not-`true` flag here
  # would quietly publish people a page asked to hide. Better to raise at the call site.
  defp filter_active(query, true),
    do: where(query, [p], is_nil(p.year_end) and is_nil(p.death_date))

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
  @doc "Delete a person. Admin-only: `{:error, :unauthorized}` otherwise."
  def delete_person(scope, %Person{} = p) do
    with :ok <- Authz.authorize_delete(scope, p), do: Repo.delete(p)
  end

  def change_person(%Person{} = p, attrs \\ %{}), do: Person.changeset(p, attrs)

  @doc "Role options as {label, value} tuples for a form select."
  def role_options, do: Enum.map(Person.roles(), &{Person.role_label(&1), &1})

  ## Pokale

  @doc "All trophies in display order."
  def list_trophies do
    Repo.all(from t in Trophy, order_by: [asc: t.sort_order, asc: t.name])
  end

  def get_trophy!(id), do: Repo.get!(Trophy, id)
  def create_trophy(attrs), do: %Trophy{} |> Trophy.changeset(attrs) |> Repo.insert()
  def update_trophy(%Trophy{} = t, attrs), do: t |> Trophy.changeset(attrs) |> Repo.update()
  def change_trophy(%Trophy{} = t, attrs \\ %{}), do: Trophy.changeset(t, attrs)

  @doc """
  Deletes a trophy that has no winners. One with winners is refused — `trophy_wins`
  restricts the delete, and the history should not vanish with a click. Admin-only:
  `{:error, :unauthorized}` otherwise.
  """
  def delete_trophy(scope, %Trophy{} = trophy) do
    with :ok <- Authz.authorize_delete(scope, trophy) do
      if Repo.exists?(from w in TrophyWin, where: w.trophy_id == ^trophy.id),
        do: {:error, :has_wins},
        else: Repo.delete(trophy)
    end
  end

  @doc "Winners, newest year first, trophy preloaded."
  def list_trophy_wins do
    Repo.all(
      from w in TrophyWin,
        join: t in assoc(w, :trophy),
        order_by: [desc: w.year, asc: t.sort_order],
        preload: [trophy: t]
    )
  end

  def get_trophy_win!(id), do: TrophyWin |> Repo.get!(id) |> Repo.preload(:trophy)
  def create_trophy_win(attrs), do: %TrophyWin{} |> TrophyWin.changeset(attrs) |> Repo.insert()

  def update_trophy_win(%TrophyWin{} = w, attrs),
    do: w |> TrophyWin.changeset(attrs) |> Repo.update()

  @doc "Delete a winner entry. Admin-only: `{:error, :unauthorized}` otherwise."
  def delete_trophy_win(scope, %TrophyWin{} = w) do
    with :ok <- Authz.authorize_delete(scope, w), do: Repo.delete(w)
  end

  def change_trophy_win(%TrophyWin{} = w, attrs \\ %{}), do: TrophyWin.changeset(w, attrs)

  @doc "Trophy options as {label, id} tuples for a form select."
  def trophy_options, do: Enum.map(list_trophies(), &{&1.name, &1.id})

  @doc """
  The Pokalsieger table: trophies (columns) and one row per year from the newest win
  down to the oldest — every year in between, so a gap (no shooting, unknown winner)
  shows as an empty row rather than vanishing.

  Returns `%{trophies: [...], rows: [{year, %{trophy_id => win}}]}`.
  """
  def trophy_table do
    trophies = list_trophies()
    wins = Repo.all(from w in TrophyWin, select: w)
    by_year = Enum.group_by(wins, & &1.year, &{&1.trophy_id, &1})

    rows =
      case Map.keys(by_year) do
        [] -> []
        years -> for y <- Enum.max(years)..Enum.min(years)//-1, do: {y, Map.new(by_year[y] || [])}
      end

    %{trophies: trophies, rows: rows}
  end

  @doc """
  Per trophy, whoever won it most often — if that is at least `min` times. Ties list
  every name. Returns `[{trophy, count, [winner]}]` in trophy order.
  """
  def trophy_records(min \\ 3) do
    counts =
      Repo.all(
        from w in TrophyWin,
          group_by: [w.trophy_id, w.winner],
          select: {w.trophy_id, w.winner, count(w.id)}
      )
      |> Enum.group_by(&elem(&1, 0), &{elem(&1, 1), elem(&1, 2)})

    for trophy <- list_trophies(),
        tally = Map.get(counts, trophy.id, []),
        tally != [],
        best = tally |> Enum.map(&elem(&1, 1)) |> Enum.max(),
        best >= min do
      {trophy, best, for({name, ^best} <- tally, do: name) |> Enum.sort()}
    end
  end
end
