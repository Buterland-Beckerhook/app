defmodule Bbh.Repo.Migrations.AddHonoraryMembers do
  use Ecto.Migration

  # The Ehrenmitglieder researched in docs/verein/ehrenmitglieder.md, as `mitglied` rows,
  # plus a draft page that lists them. Nothing here is public: the people only show up
  # through a Personenliste block, and the page stays a draft until the data is complete.
  #
  # Skipped per name when that person already carries an appointment year (the office
  # holders the previous migration marked). Year unknown = 1900 (never rendered). Known
  # deaths are set; several more members are dead without a known date — they are listed
  # in the doc and still need one, or they show among the living.
  #
  # Only on the club's database (imported throne list present), so tests start empty.

  # {name, honorary_since, death_date, biography}
  @members [
    {"Anton Sundag", 1900, nil,
     "Auf dem Foto der Ehrenmitglieder zum Jubiläum 1984. Nicht zu verwechseln mit Oberst Anton Sundag (1847–1929)."},
    {"Wilhelm Appels", 1900, nil, "Auf dem Foto der Ehrenmitglieder zum Jubiläum 1984."},
    {"Heinrich Lütke-Glanemann", 1900, nil,
     "Auf dem Foto der Ehrenmitglieder zum Jubiläum 1984."},
    {"Josef Verst", 1900, nil,
     "Auf dem Foto der Ehrenmitglieder zum Jubiläum 1984 (die Bildunterschrift nennt den Namen zweimal)."},
    {"Bernhard Albers", 1900, nil, "Auf dem Foto der Ehrenmitglieder zum Jubiläum 1984."},
    {"Hermann Hackfort", 1900, nil,
     "Mitglied des Seniorenausschusses. Gewann den Seniorenpokal 1989, 1997 und 1998."},
    {"Alfons Diekmann", 1900, nil,
     "Baute über vier Jahrzehnte die Königsvögel des Vereins und war von 1962 bis 1987 Offizier."},
    {"Franz Doetkotte", 1900, nil, nil},
    {"Otto Storost", 1900, ~D[2020-07-29],
     "Mitglied des Seniorenausschusses. Gewann den Seniorenpokal 1983 und 1993."},
    {"Franz Nacke", 1900, nil,
     "Mitglied des Seniorenausschusses. Verfasste den Beitrag über das Vereinslokal in der Festschrift 1984."},
    {"Theodor Gründken", 1900, nil, "König 1979/80."},
    {"Bernhard Niehoff", 1900, nil, "2023 für 75 Jahre Mitgliedschaft geehrt."},
    {"Alfons Gründken", 1900, nil,
     "Mitglied des Seniorenausschusses, für 70 Jahre Vereinstreue mit dem Ehrenorden ausgezeichnet."},
    {"Gerd Dornhege", 1900, nil, "König 1986/87, später Oberstleutnant."},
    {"Alfons Kühlkamp", 1900, nil, "Mitglied des Seniorenausschusses."},
    {"Karl-Heinz Hork", 1900, nil, "König 1987/88."},
    {"Gerd Duesmann", 1900, nil,
     "König im Jubiläumsjahr 1984/85, später Vizepräsident und im Seniorenausschuss."},
    {"Josef Blömer", 1900, nil, nil},
    {"Joachim Diekmann", 2021, nil, "König 1991/92."},
    {"Bernhard Schmeing", 2021, nil, "König 2006/07."},
    {"Alois Verst", 2021, nil, "König 1982/83, später Oberstleutnant."},
    {"Hermann Thebelt", 2021, nil,
     "König 1977/78 und 1993/94, Jubiläumskaiser 1984. Stifter des Königspokals."},
    {"Josef Lütke-Glanemann", 2021, nil, nil},
    {"Norbert Wülker", 2022, nil,
     "Gehörte 31 Jahre dem Offizierscorps an, zuletzt als Oberstleutnant."},
    {"Andreas Lösing", 2023, nil,
     "König 1992/93 und Gronauer Stadtkaiser 2011; engagiert in den Ausschüssen des Vereins."},
    {"Georg Doetkotte", 2024, nil,
     "König 2001/02, 30 Jahre im Offizierscorps; engagiert in den Ausschüssen des Vereins."},
    {"Heinrich Thebelt", 2024, nil,
     "König 1997/98. Als Wirt des Vereinslokals Dinkelhof beherbergt er Fahnen, Ketten und Utensilien des Vereins."}
  ]

  @intro "<p>Mitglieder, die sich in besonderer Weise um den Schützenverein " <>
           "Buterland-Beckerhook verdient gemacht haben, ernennt der Verein zu " <>
           "Ehrenmitgliedern. Wir danken ihnen für ihre Treue und ihren Einsatz.</p>"

  def up do
    %{rows: [[club_db?]]} =
      repo().query!("SELECT EXISTS (SELECT 1 FROM articles WHERE slug = 'thron' AND year = 1909)")

    if club_db? do
      Enum.with_index(@members, fn member, i -> insert_member(member, i) end)
      create_page()
    end
  end

  def down, do: :ok

  defp insert_member({name, since, death, bio}, index) do
    repo().query!(
      """
      INSERT INTO people (id, name, role, honorary_since, death_date, biography, sort_order,
                          inserted_at, updated_at)
      SELECT gen_random_uuid(), $1::varchar, 'mitglied', $2::int, $3::date, $4::text, $5::int,
             now(), now()
      WHERE NOT EXISTS (
        SELECT 1 FROM people WHERE name = $1::varchar AND honorary_since IS NOT NULL
      )
      """,
      [name, since, death, bio && "<p>#{bio}</p>", index]
    )
  end

  # Draft and unlisted: it goes into the menu (probably under „Über uns") when the
  # appointment years and death dates are in.
  defp create_page do
    %{rows: rows} =
      repo().query!("""
      INSERT INTO pages (id, status, title, slug, sort_order, placement, noindex,
                         inserted_at, updated_at)
      VALUES (gen_random_uuid(), 'draft', 'Ehrenmitglieder', 'ehrenmitglieder', 0,
              'unlisted', false, now(), now())
      ON CONFLICT (slug) DO NOTHING
      RETURNING id
      """)

    for [page_id] <- rows do
      %{rows: [[text_id]]} =
        repo().query!(
          """
          INSERT INTO block_richtext (id, body, inserted_at, updated_at)
          VALUES (gen_random_uuid(), $1, now(), now()) RETURNING id
          """,
          [@intro]
        )

      lists =
        for {title, alive} <- [{nil, "living"}, {"Verstorbene Ehrenmitglieder", "deceased"}] do
          %{rows: [[id]]} =
            repo().query!(
              """
              INSERT INTO block_person_list (id, title, filter_roles, filter_honorary,
                                             filter_alive, display_style, show_address,
                                             only_active, sort_by, inserted_at, updated_at)
              VALUES (gen_random_uuid(), $1, '{}', 'only', $2, 'cards', false, false,
                      'honorary_since', now(), now())
              RETURNING id
              """,
              [title, alive]
            )

          id
        end

      blocks = [{"richtext", text_id} | Enum.map(lists, &{"person_list", &1})]

      for {{type, block_id}, pos} <- Enum.with_index(blocks) do
        repo().query!(
          """
          INSERT INTO page_blocks (id, page_id, position, block_type, block_id,
                                   inserted_at, updated_at)
          VALUES (gen_random_uuid(), $1, $2, $3, $4, now(), now())
          """,
          [page_id, pos, type, block_id]
        )
      end
    end
  end
end
