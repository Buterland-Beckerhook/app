defmodule Bbh.Repo.Migrations.SplitCommaTags do
  use Ecto.Migration

  # The import from the old site stored some tag lists as one string ("Biwak, Corona").
  # Split them into separate tags, keeping their order and dropping repeats. New writes
  # can't produce these any more (`Bbh.Content.Article.normalize_tags/1`).

  def up do
    execute """
    UPDATE articles a
    SET tags = fixed.tags
    FROM (
      SELECT id, array_agg(tag ORDER BY pos) AS tags
      FROM (
        SELECT a.id, trim(part.tag) AS tag, min(t.ord * 1000 + part.ord) AS pos
        FROM articles a,
             unnest(a.tags) WITH ORDINALITY AS t(val, ord),
             unnest(string_to_array(t.val, ',')) WITH ORDINALITY AS part(tag, ord)
        WHERE trim(part.tag) <> ''
        GROUP BY a.id, trim(part.tag)
      ) parts
      GROUP BY id
    ) fixed
    WHERE a.id = fixed.id
      AND EXISTS (SELECT 1 FROM unnest(a.tags) t WHERE t LIKE '%,%')
    """
  end

  def down, do: :ok
end
