defmodule Bbh.Repo.Migrations.AddEarlyThronesFromFestschrift1959 do
  use Ecto.Migration

  # The Festschrift 1959 lists every king since 1909 (p. 37); eleven of them, and the
  # Kaiser of 1922, never made it onto /thron. Each king gets what the existing early
  # thrones have: a published „Nur Thron-Anzeige" article (no_article, never pushed) plus
  # its throne row. The Kaiser is only reachable through his article (the Thron menu
  # links Kaiser reigns, it has no list), so that one is a real article, created as a
  # draft through the MCP endpoint; here it only gets its throne, if it exists. Regnal numbers are derived from the list and agree with every number
  # already stored (Hubert II. 1949, Heinrich V. 1950, Wilhelm III. 1954, Bernhard IV.
  # 1956) and with Gleis-Preister's „Gerhard V." of 1964. Queens are given as printed
  # ("Frau Heinrich Sundag"). The date is a placeholder for ordering — mid-July, like
  # the neighbouring years. Skipped where an article for that year already exists, and
  # entirely on a database without the imported throne list (tests, a fresh dev setup) —
  # this completes that list, it does not seed one.
  # Source and caveats: docs/verein/quellen.md.

  # {year, end, king_title, king, queen}
  @kings [
    {1911, 1912, "Wilhelm I.", "Wilhelm Subgang", "Dina Gleis"},
    {1913, 1921, "Gerhard II.", "Gerhard Lammers", "Frau Gerhard Agten"},
    {1921, 1922, "Bernhard III.", "Bernhard Möllen", "Maria Dornhege"},
    {1924, 1925, "Julius I.", "Julius Schemmer", "Frau Heinrich Sundag"},
    {1925, 1926, "Gerhard III.", "Gerhard Rensing", "Frau Hermann Lewing"},
    {1926, 1927, "Hermann I.", "Hermann Lammers", "Frau Heinrich Piepenpott"},
    {1927, 1928, "Wilhelm II.", "Wilhelm Veddler", "Henerika Kwekkeboom"},
    {1931, 1932, "Hubert I.", "Hubert Beyer", "Änne ten Venne"},
    {1934, 1935, "Gerhard IV.", "Gerhard Schreiber", "Frau Heinrich Beerlage"},
    {1937, 1938, "Heinrich III.", "Heinrich Feldevert", "Frau Fritz Dropmann"},
    {1938, 1939, "Heinrich IV.", "Heinrich Thebelt", "Frau Hermann Gleis"}
  ]

  def up do
    %{rows: [[imported?]]} =
      repo().query!("SELECT EXISTS (SELECT 1 FROM articles WHERE slug = 'thron' AND year = 1909)")

    if imported?, do: complete_list()
  end

  defp complete_list do
    for {year, finish, title, king, queen} <- @kings do
      span = if finish == year + 1, do: "#{year}/#{finish}", else: "#{year}-#{finish}"

      insert(year, "thron", "Thron #{span} - #{title}", ["Thron"],
        type: "koenig",
        begin: year,
        end: finish,
        king_title: title,
        king: king,
        queen: queen
      )
    end

    repo().query!(
      """
      INSERT INTO thrones (id, article_id, type, "begin", king, queen, inserted_at, updated_at)
      SELECT gen_random_uuid(), a.id, 'kaiser', 1922, 'Gerhard Agten', 'Frau Johann Nieuwmeyer',
             now(), now()
      FROM articles a
      WHERE a.slug = 'kaiserthron' AND a.year = 1922
        AND NOT EXISTS (SELECT 1 FROM thrones t WHERE t.article_id = a.id)
      """,
      []
    )

    # Typo in the imported title.
    execute """
    UPDATE articles SET title = 'Thron 1935/1936 - Franz I.'
    WHERE year = 1935 AND slug = 'thron' AND title = 'Thron 1935/1036 - Franz I.'
    """
  end

  def down, do: :ok

  defp insert(year, slug, title, tags, throne) do
    %{rows: rows} =
      repo().query!(
        """
        INSERT INTO articles (id, status, title, slug, date_published, year, tags, no_article,
                              aliases, notified_at, inserted_at, updated_at)
        SELECT gen_random_uuid(), 'published', $1::varchar, $2::varchar,
               make_timestamp($3::int, 7, 15, 19, 0, 0), $3::int, $4::varchar[], true, '{}',
               now(), now(), now()
        WHERE NOT EXISTS (SELECT 1 FROM articles WHERE slug = $2::varchar AND year = $3::int)
        RETURNING id
        """,
        [title, slug, year, tags]
      )

    for [article_id] <- rows do
      columns = Keyword.keys(throne)
      params = Keyword.values(throne)
      placeholders = Enum.map_join(1..length(params), ", ", &"$#{&1 + 1}")
      column_list = Enum.map_join(columns, ", ", &~s("#{&1}"))

      repo().query!(
        """
        INSERT INTO thrones (id, article_id, #{column_list}, inserted_at, updated_at)
        VALUES (gen_random_uuid(), $1, #{placeholders}, now(), now())
        """,
        [article_id | params]
      )
    end
  end
end
