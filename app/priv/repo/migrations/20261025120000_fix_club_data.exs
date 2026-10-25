defmodule Bbh.Repo.Migrations.FixClubData do
  use Ecto.Migration

  # Content errors found while comparing the site against the old club pages
  # (docs/content-plan.md §2). Every statement is guarded by the wrong value it fixes, so
  # a row an editor has already corrected is left alone and re-running is harmless.
  # Irreversible on purpose: `down` would only reintroduce the errors.
  def up do
    # Gerhard Gleis-Preister handed the presidency to Heinz Verst on 21.11.1998.
    execute """
    UPDATE people SET year_end = 1998
    WHERE name = 'Gerhard Gleis-Preister' AND role = 'praesident' AND year_end = 2018
    """

    # The card already prints its own "*"; the stored one doubled it.
    execute """
    UPDATE people SET birth_date = regexp_replace(birth_date, '^\\*\\s*', '')
    WHERE birth_date LIKE '*%'
    """

    # The 1930/31 throne article was imported without its throne, so /thron skipped it.
    insert_throne("thron", 1930,
      type: "koenig",
      begin: 1930,
      end: 1931,
      king_title: "Heinrich II.",
      king: "Heinrich Meyer",
      queen: "Elisabeth Feldevert"
    )

    # Our three earlier Stadtkaiser (2025 already has its throne). Their articles were
    # created as drafts through the MCP endpoint; where one doesn't exist (dev snapshots,
    # tests) this is a no-op.
    insert_throne("stadtkaiser", 2000,
      type: "stadtkaiser",
      begin: 2000,
      king: "Ludger Bußjan",
      queen: "Birgit Theissing"
    )

    insert_throne("stadtkaiser", 2011,
      type: "stadtkaiser",
      begin: 2011,
      king: "Andreas Lösing",
      queen: "Renate Büscher"
    )

    insert_throne("stadtkaiser", 2022,
      type: "stadtkaiser",
      begin: 2022,
      king: "Martin Schreiber",
      queen: "Maria Oude Lansink"
    )
  end

  def down, do: :ok

  defp insert_throne(slug, year, fields) do
    columns = Keyword.keys(fields)
    params = Keyword.values(fields)
    placeholders = Enum.map_join(1..length(params), ", ", &"$#{&1 + 2}")
    column_list = Enum.map_join(columns, ", ", &~s("#{&1}"))

    repo().query!(
      """
      INSERT INTO thrones (id, article_id, #{column_list}, inserted_at, updated_at)
      SELECT gen_random_uuid(), a.id, #{placeholders}, now(), now()
      FROM articles a
      WHERE a.slug = $1 AND a.year = $2
        AND NOT EXISTS (SELECT 1 FROM thrones t WHERE t.article_id = a.id)
      """,
      [slug, year | params]
    )
  end
end
