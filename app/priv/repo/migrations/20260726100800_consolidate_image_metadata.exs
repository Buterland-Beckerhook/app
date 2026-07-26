defmodule Bbh.Repo.Migrations.ConsolidateImageMetadata do
  use Ecto.Migration

  @moduledoc """
  Caption/description/copyright become properties of the media item itself, edited
  only in the media library. An embedding (article image, gallery file) keeps just
  its embedding decisions — whether to show the caption, throne picture, sort.

  The existing per-embedding values are folded into `media` first, and in every case the
  **media value wins**: it is the curated one (editable in the library since 2026-07-15),
  while `article_images.copyright` carries a column *default*
  (`'Buterland-Beckerhook e.V.'`, see 20260713150853) that nobody typed. Preferring the
  embedding would therefore overwrite a photographer credit an editor had entered in the
  library with a default — silently, and with no way back. Aggregating with `min()` keeps
  the fold deterministic even if one media item were embedded twice with differing text;
  where a still-empty media field could be filled from *both* an article image and a
  gallery file, the statement order below decides it (the article one runs first).

  `down` recreates the dropped columns empty and does **not** revert the `media` rows this
  migration filled in — a rollback is not a restore.
  """

  def up do
    execute """
    UPDATE media m SET
      caption = COALESCE(NULLIF(m.caption, ''), NULLIF(x.title, '')),
      description = COALESCE(NULLIF(m.description, ''), NULLIF(x.description, '')),
      copyright = COALESCE(NULLIF(m.copyright, ''), NULLIF(x.copyright, ''))
    FROM (
      SELECT media_id, min(title) AS title, min(description) AS description,
             min(copyright) AS copyright
      FROM article_images GROUP BY media_id
    ) x
    WHERE x.media_id = m.id
    """

    execute """
    UPDATE media m SET
      caption = COALESCE(NULLIF(m.caption, ''), NULLIF(x.title, '')),
      copyright = COALESCE(NULLIF(m.copyright, ''), NULLIF(x.copyright, ''))
    FROM (
      SELECT media_id, min(title) AS title, min(copyright) AS copyright
      FROM block_gallery_files GROUP BY media_id
    ) x
    WHERE x.media_id = m.id
    """

    alter table(:article_images) do
      # Per-embedding: show the media item's caption under this image or not.
      add :show_caption, :boolean, null: false, default: true

      remove :title
      remove :description
      remove :copyright
    end

    alter table(:block_gallery_files) do
      remove :title
      remove :copyright
    end
  end

  def down do
    alter table(:article_images) do
      remove :show_caption

      add :title, :string
      add :description, :string
      add :copyright, :string, default: "Buterland-Beckerhook e.V."
    end

    alter table(:block_gallery_files) do
      add :title, :string
      add :copyright, :string
    end
  end
end
