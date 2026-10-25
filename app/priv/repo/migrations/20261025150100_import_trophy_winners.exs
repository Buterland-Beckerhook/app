defmodule Bbh.Repo.Migrations.ImportTrophyWinners do
  use Ecto.Migration

  # The five Pokale and every known winner 1969–2026 (docs/verein/pokalschiessen.md,
  # one row per winner in priv/repo/data/pokalsieger.tsv), plus a draft page that shows
  # them. Only on the club's database — recognised by the imported throne list — so a
  # test or fresh dev database starts empty. Skipped entirely once any trophy exists.

  @trophies [
    {"schuetzenpokal", "Schützenpokal", 1965, 1,
     "Für alle Mitglieder (Junioren und Senioren schießen um ihren eigenen Pokal). " <>
       "1965 als Wanderpokal von König Gerd VI. (Gleis-Preister) gestiftet, " <>
       "1981 neu vom Verein gestiftet."},
    {"juniorenpokal", "Juniorenpokal", 1966, 2,
     "Für Mitglieder bis zum 23. Lebensjahr. 1966 vom Verein gestiftet."},
    {"seniorenpokal", "Seniorenpokal", 1981, 3,
     "Wanderpokal für Mitglieder ab dem vollendeten 55. Lebensjahr."},
    {"koenigspokal", "Königspokal", 1996, 4,
     "Nur für die Könige und Kaiser des Vereins. 1996 von Kaiser Hermann Thebelt gestiftet."},
    {"biwakpokal", "Biwakpokal", 1975, 5,
     "Wird beim Biwak im Mai ausgeschossen; seit 1977 ein Wanderpreis."}
  ]

  @intro """
  <p>Am ersten Samstag des neuen Jahres treffen sich die Schützen zum traditionellen
  Pokal- und Preisschießen im Vereinslokal Dinkelhof. Neben den Pokalen geht es beim
  Preisschießen um attraktive Sachpreise. Die Pokale werden auf dem Winterfest überreicht.
  Der Biwakpokal wird beim Biwak im Mai ausgeschossen.</p>
  <p>Organisiert wird das Schießen von der Schießriege. Sie wurde 1988 gegründet – Anlass
  war ein Vergleichsschießen der Gronauer und Eper Schützenvereine.</p>
  """

  def up do
    %{rows: [[club_db?]]} =
      repo().query!("""
      SELECT EXISTS (SELECT 1 FROM articles WHERE slug = 'thron' AND year = 1909)
         AND NOT EXISTS (SELECT 1 FROM trophies)
      """)

    if club_db?, do: import!()
  end

  def down, do: :ok

  defp import!() do
    ids =
      for {key, name, since, sort, description} <- @trophies, into: %{} do
        %{rows: [[id]]} =
          repo().query!(
            """
            INSERT INTO trophies (id, name, since, description, sort_order, inserted_at, updated_at)
            VALUES (gen_random_uuid(), $1, $2, $3, $4, now(), now())
            RETURNING id
            """,
            [name, since, description, sort]
          )

        {key, id}
      end

    for {key, year, winner, rings} <- winners() do
      repo().query!(
        """
        INSERT INTO trophy_wins (id, trophy_id, year, winner, rings, inserted_at, updated_at)
        VALUES (gen_random_uuid(), $1, $2, $3, $4, now(), now())
        """,
        [Map.fetch!(ids, key), year, winner, rings]
      )
    end

    create_page!()
  end

  defp winners do
    Path.join(:code.priv_dir(:bbh), "repo/data/pokalsieger.tsv")
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "#"))
    |> Enum.map(fn line ->
      [key, year, winner, rings] = String.split(line, "\t")

      {key, String.to_integer(year), winner,
       if(rings == "", do: nil, else: String.to_integer(rings))}
    end)
  end

  # A draft, top-level and unlisted until someone files it into the menu — where it
  # belongs in „Der Verein" is an editorial call.
  defp create_page! do
    %{rows: [[page_id]]} =
      repo().query!("""
      INSERT INTO pages (id, status, title, slug, sort_order, placement, noindex,
                         inserted_at, updated_at)
      VALUES (gen_random_uuid(), 'draft', 'Pokalschießen', 'pokalschiessen', 0, 'unlisted',
              false, now(), now())
      ON CONFLICT (slug) DO NOTHING
      RETURNING id
      """)
      |> case do
        %{rows: []} -> %{rows: [[nil]]}
        result -> result
      end

    if page_id do
      %{rows: [[text_id]]} =
        repo().query!(
          """
          INSERT INTO block_richtext (id, body, inserted_at, updated_at)
          VALUES (gen_random_uuid(), $1, now(), now()) RETURNING id
          """,
          [String.replace(@intro, ~r/\n\s*/, " ") |> String.trim()]
        )

      %{rows: [[table_id]]} =
        repo().query!("""
        INSERT INTO block_trophy_table (id, title, show_records, show_descriptions,
                                        inserted_at, updated_at)
        VALUES (gen_random_uuid(), 'Pokalsieger', true, true, now(), now()) RETURNING id
        """)

      for {type, block_id, pos} <- [{"richtext", text_id, 0}, {"trophy_table", table_id, 1}] do
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
