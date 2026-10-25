defmodule Bbh.Repo.Migrations.PeopleHonorarySinceAndDates do
  use Ecto.Migration

  # Three changes to `people` for the Ehrenmitglieder page (docs/content-plan.md §1.2):
  #
  #   * `honorary_since` (year) replaces the `honorary_member` flag — set means honorary
  #     member. 1900 stands for "year unknown" and is never rendered.
  #   * `birth_date` / `death_date` become real dates; the place that trailed the free text
  #     ("19. Februar 1929 in Gronau") moves to `birth_place` / `death_place`.
  #   * A person has one row: Hermann Lewing's Oberst row goes, his Präsident row stays
  #     (its biography already covers the Oberst years).
  #
  # Every existing value must parse, or the migration raises before anything is written —
  # a date that silently became NULL would be lost for good.

  @months ~w(Januar Februar März April Mai Juni Juli August September Oktober November Dezember)

  # Appointment years the sources name (docs/verein/ehrenmitglieder.md). Everyone else who
  # carried the flag gets the placeholder year.
  @honorary_years %{
    "Theodor Eimann" => 1921,
    "Friedrich Dropmann" => 1955,
    "Heinrich Pieper" => 1966,
    "Heinrich Lammers" => 1978,
    "Heinz Verst" => 2018,
    "Michael Terhalle" => 2018
  }

  # Honorary members the old flag missed; their year is unknown.
  @honorary_unflagged ["Wilhelm Hoff", "Josef Tönjann"]

  @unknown_year 1900

  def up do
    alter table(:people) do
      add :honorary_since, :integer
      add :birth_place, :string
      add :death_place, :string
      add :birth_on, :date
      add :death_on, :date
    end

    flush()

    %{rows: rows} =
      repo().query!("SELECT id, name, honorary_member, birth_date, death_date FROM people")

    parsed =
      for [id, name, honorary?, birth, death] <- rows do
        {id, name, honorary?, parse(birth), parse(death)}
      end

    case for({_, name, _, b, d} <- parsed, {:error, raw} <- [b, d], do: "#{name}: #{raw}") do
      [] -> :ok
      bad -> raise "unparsable people dates, fix them first:\n" <> Enum.join(bad, "\n")
    end

    for {id, name, honorary?, {:ok, birth_on, birth_place}, {:ok, death_on, death_place}} <-
          parsed do
      repo().query!(
        """
        UPDATE people
        SET birth_on = $2, birth_place = $3, death_on = $4, death_place = $5,
            honorary_since = $6
        WHERE id = $1
        """,
        [id, birth_on, birth_place, death_on, death_place, honorary_since(name, honorary?)]
      )
    end

    execute """
    DELETE FROM people o
    WHERE o.name = 'Hermann Lewing' AND o.role = 'oberst'
      AND EXISTS (SELECT 1 FROM people p WHERE p.name = o.name AND p.role = 'praesident')
    """

    alter table(:people) do
      remove :honorary_member
      remove :birth_date
      remove :death_date
    end

    rename table(:people), :birth_on, to: :birth_date
    rename table(:people), :death_on, to: :death_date

    create constraint(:people, :people_honorary_since_range,
             check: "honorary_since IS NULL OR honorary_since >= #{@unknown_year}"
           )
  end

  # Back to free text in the shape the cards used to print; the deleted Oberst row and the
  # exact original spelling ("09." vs "9.", "im"/"in") are not restored.
  def down do
    drop constraint(:people, :people_honorary_since_range)

    alter table(:people) do
      add :honorary_member, :boolean, null: false, default: false
      add :birth_text, :string
      add :death_text, :string
    end

    flush()

    %{rows: rows} =
      repo().query!(
        "SELECT id, birth_date, birth_place, death_date, death_place, honorary_since FROM people"
      )

    for [id, bd, bp, dd, dp, since] <- rows do
      repo().query!(
        "UPDATE people SET birth_text = $2, death_text = $3, honorary_member = $4 WHERE id = $1",
        [id, to_text(bd, bp), to_text(dd, dp), not is_nil(since)]
      )
    end

    alter table(:people) do
      remove :birth_date
      remove :death_date
      remove :birth_place
      remove :death_place
      remove :honorary_since
    end

    rename table(:people), :birth_text, to: :birth_date
    rename table(:people), :death_text, to: :death_date
  end

  defp honorary_since(name, honorary?) do
    cond do
      year = @honorary_years[name] -> year
      honorary? or name in @honorary_unflagged -> @unknown_year
      true -> nil
    end
  end

  # "* 21. Juli 1942 in Gronau", "09. Mai 1862 in Warendorf", "6. Mai 1847 im Kirchspiel
  # Epe", "23. Januar 1887 Kirchspiel Epe", "24. August 1965". The place keeps a
  # preposition other than "in" ("im Kirchspiel Epe"), which the card then prints as is.
  defp parse(nil), do: {:ok, nil, nil}

  defp parse(raw) do
    text = raw |> String.trim() |> String.replace(~r/^\*\s*/, "")

    with [_, day, month, year, rest] <-
           Regex.run(~r/^(\d{1,2})\.\s*(\p{L}+)\s+(\d{4})\s*(.*)$/u, text),
         index when is_integer(index) <- Enum.find_index(@months, &(&1 == month)),
         {:ok, date} <-
           Date.new(String.to_integer(year), index + 1, String.to_integer(day)) do
      {:ok, date, place(String.trim(rest))}
    else
      _ -> {:error, raw}
    end
  end

  defp place(""), do: nil
  defp place("in " <> place), do: String.trim(place)
  defp place("Kirchspiel " <> _ = place), do: "im " <> place
  defp place(place), do: place

  defp to_text(nil, _), do: nil

  defp to_text(date, place) do
    text = "#{date.day}. #{Enum.at(@months, date.month - 1)} #{date.year}"

    case place do
      nil -> text
      "im " <> _ -> "#{text} #{place}"
      _ -> "#{text} in #{place}"
    end
  end
end
