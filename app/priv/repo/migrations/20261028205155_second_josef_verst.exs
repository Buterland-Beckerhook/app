defmodule Bbh.Repo.Migrations.SecondJosefVerst do
  use Ecto.Migration

  # The photo of the Ehrenmitglieder at the 1984 jubilee names „Josef Verst" twice, and the
  # caption matches the number of people on it: there were two. The one we know is the
  # Jubiläumskönig 1959 († 2013); the other gets a row of his own, year unknown (1900).
  #
  # Only on the club's database (imported throne list present), and only while there is
  # just the one Josef Verst, so a rerun or a row added in the admin isn't duplicated.

  @known_bio_note " (die Bildunterschrift nennt den Namen zweimal)"

  @second_bio "Auf dem Foto der Ehrenmitglieder zum Jubiläum 1984. Nicht zu verwechseln " <>
                "mit dem Jubiläumskönig 1959 Josef Verst (1920–2013)."

  def up do
    %{rows: [[club_db?]]} =
      repo().query!("SELECT EXISTS (SELECT 1 FROM articles WHERE slug = 'thron' AND year = 1909)")

    if club_db? do
      repo().query!(
        """
        INSERT INTO people (id, name, role, honorary_since, biography, sort_order,
                            inserted_at, updated_at)
        SELECT gen_random_uuid(), 'Josef Verst', 'mitglied', 1900, $1::text,
               (SELECT coalesce(max(sort_order), -1) + 1 FROM people
                WHERE role = 'mitglied' AND honorary_since IS NOT NULL),
               now(), now()
        WHERE (SELECT count(*) FROM people WHERE name = 'Josef Verst') = 1
        """,
        ["<p>#{@second_bio}</p>"]
      )
    end

    repo().query!(
      """
      UPDATE people SET biography = replace(biography, $1::text, ''), updated_at = now()
      WHERE name = 'Josef Verst' AND birth_date = '1920-10-19'
        AND biography LIKE '%' || $1::text || '%'
      """,
      [@known_bio_note]
    )
  end

  def down, do: :ok
end
