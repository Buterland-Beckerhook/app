defmodule Bbh.Repo.Migrations.HonoraryMembersFromObituaries do
  use Ecto.Migration

  # Life dates and service records of Ehrenmitglieder who died since 2013, taken from the
  # club's own obituaries on trauer.ms (docs/verein/ehrenmitglieder.md, „Quellen").
  #
  # Dates only fill empty fields. A biography is only replaced while it still reads as
  # 20261025140200_add_honorary_members wrote it, so an edit made in the admin since wins.
  # Rows are matched by name among honorary members; a name that isn't there is skipped.
  #
  # Erich Zgodda is new: the doc had him as a maybe, the club's obituary (2012) calls him
  # „unser Ehrenmitglied". Inserted like 20261025140200 did, only on the club's database.

  @zgodda_bio "Gründete 1990 den Kinderfestausschuss, der 1991 das erste Kinderfest " <>
                "ausrichtete, und leitete ihn bis 2000. Ebenfalls 1990 gestaltete er das " <>
                "Thronbild, das im Festzelt über dem Thron hängt."

  # {name, birth_date, death_date, biography as written before (nil = none), new biography}
  @members [
    {"Hermann Hackfort", ~D[1933-03-04], ~D[2015-03-06],
     "Mitglied des Seniorenausschusses. Gewann den Seniorenpokal 1989, 1997 und 1998.",
     "Gehörte 30 Jahre lang, bis 2005, dem Vorstand an und kümmerte sich um den Schützenplatz. Im Seniorenausschuss; gewann den Seniorenpokal 1989, 1997 und 1998."},
    {"Alfons Diekmann", ~D[1932-05-21], ~D[2016-10-28],
     "Baute über vier Jahrzehnte die Königsvögel des Vereins und war von 1962 bis 1987 Offizier.",
     "Baute über 50 Jahre die Königsvögel des Vereins und gehörte von 1962 bis 1987 dem Offizierscorps an."},
    {"Franz Doetkotte", ~D[1933-07-28], ~D[2019-11-13], nil,
     "Gehörte fast 30 Jahre dem Offizierscorps an."},
    {"Otto Storost", ~D[1924-12-17], ~D[2020-07-29],
     "Mitglied des Seniorenausschusses. Gewann den Seniorenpokal 1983 und 1993.",
     "67 Jahre Mitglied des Vereins. Im Seniorenausschuss; gewann den Seniorenpokal 1983 und 1993."},
    {"Franz Nacke", ~D[1925-06-27], ~D[2023-07-03],
     "Mitglied des Seniorenausschusses. Verfasste den Beitrag über das Vereinslokal in der Festschrift 1984.",
     "Gehörte 24 Jahre dem Vorstand an, von 1981 bis 1991 als Geschäftsführer und bis 1993 als Vizepräsident. Die Festschrift zum 75-jährigen Jubiläum 1984 erstellte er beinahe allein. Später im Seniorenausschuss."},
    {"Theodor Gründken", ~D[1931-05-25], ~D[2021-02-01], "König 1979/80.",
     "König 1979/80. Gehörte 32 Jahre dem Offizierscorps an und war viele Jahrzehnte Schießmeister des Vereins."},
    {"Gerd Dornhege", ~D[1950-07-30], ~D[2021-02-12], "König 1986/87, später Oberstleutnant.",
     "König 1986/87. Gehörte 35 Jahre dem Offizierscorps an, davon zwölf Jahre als Major und sieben als Oberstleutnant."},
    {"Alfons Kühlkamp", ~D[1940-04-20], ~D[2020-10-29], "Mitglied des Seniorenausschusses.",
     "Gehörte 36 Jahre dem Vorstand an, davon 20 Jahre als Kassierer. Später im Seniorenausschuss."},
    {"Karl-Heinz Hork", ~D[1940-09-19], ~D[2022-10-03], "König 1987/88.",
     "König 1987/88. Gehörte 30 Jahre dem Vorstand an."},
    {"Gerd Duesmann", ~D[1945-03-09], ~D[2023-11-06],
     "König im Jubiläumsjahr 1984/85, später Vizepräsident und im Seniorenausschuss.",
     "König im Jubiläumsjahr 1984/85. Gehörte 38 Jahre dem Vorstand an, davon 21 Jahre als Vizepräsident, und kümmerte sich zuletzt um die Senioren des Vereins."},
    {"Josef Verst", ~D[1920-10-19], ~D[2013-01-20],
     "Auf dem Foto der Ehrenmitglieder zum Jubiläum 1984 (die Bildunterschrift nennt den Namen zweimal).",
     "König im Jubiläumsjahr 1959/60. Gehörte von 1951 bis 1983 dem Offizierscorps an, seit 1962 als Major. Auf dem Foto der Ehrenmitglieder zum Jubiläum 1984 (die Bildunterschrift nennt den Namen zweimal)."},
    {"Wilhelm Hoff", ~D[1942-07-21], ~D[2024-07-06], nil, nil}
  ]

  def up do
    for member <- @members, do: update_member(member)

    %{rows: [[club_db?]]} =
      repo().query!("SELECT EXISTS (SELECT 1 FROM articles WHERE slug = 'thron' AND year = 1909)")

    if club_db?, do: insert_zgodda()

    # Wilhelm Hoff was König 2000/01 (throne list and the club's obituary), not 1999/2000.
    execute """
    UPDATE people
    SET biography = replace(biography, 'Als Wilhelm VIII. war er 1999/2000 König.',
                            'Als Wilhelm VIII. war er 2000/01 König.'),
        updated_at = now()
    WHERE name = 'Wilhelm Hoff' AND biography LIKE '%Als Wilhelm VIII. war er 1999/2000 König.%'
    """
  end

  def down, do: :ok

  defp insert_zgodda do
    repo().query!(
      """
      INSERT INTO people (id, name, role, honorary_since, birth_date, death_date, biography,
                          sort_order, inserted_at, updated_at)
      SELECT gen_random_uuid(), 'Erich Zgodda', 'mitglied', 1900, '1929-03-24', '2012-01-13',
             $1::text, (SELECT coalesce(max(sort_order), -1) + 1 FROM people
                        WHERE role = 'mitglied' AND honorary_since IS NOT NULL),
             now(), now()
      WHERE NOT EXISTS (SELECT 1 FROM people WHERE name = 'Erich Zgodda')
      """,
      ["<p>#{@zgodda_bio}</p>"]
    )
  end

  defp update_member({name, birth, death, old_bio, new_bio}) do
    repo().query!(
      """
      UPDATE people
      SET birth_date = coalesce(birth_date, $2::date),
          death_date = coalesce(death_date, $3::date),
          biography = CASE
            WHEN $5::text IS NOT NULL AND coalesce(biography, '') = coalesce($4::text, '')
            THEN $5::text ELSE biography END,
          updated_at = now()
      WHERE name = $1::varchar AND honorary_since IS NOT NULL
      """,
      [name, birth, death, old_bio && "<p>#{old_bio}</p>", new_bio && "<p>#{new_bio}</p>"]
    )
  end
end
