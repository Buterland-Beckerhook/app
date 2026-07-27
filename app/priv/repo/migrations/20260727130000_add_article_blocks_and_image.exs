defmodule Bbh.Repo.Migrations.AddArticleBlocksAndImage do
  use Ecto.Migration

  # Brings the page block system (the Directus M2A `block_*` tables) to articles via a
  # parallel `article_blocks` join, gives each article one first-class `image_id`, and
  # lets a throne carry its own `image_id` (null = inherit the article image).
  #
  # The data backfill converts every existing article losslessly into the shape the
  # public page rendered before: the rich-text `body` becomes one `richtext` block, the
  # non-hero images become one grid `image_gallery` block, and the hero becomes the
  # article image. The legacy `articles.body` column and `article_images` table are left
  # in place (unread) so this migration is reversible; a follow-up migration drops them
  # once the conversion is verified in production.
  #
  # Raw SQL throughout: a data migration must not reference the app's Ecto schemas, whose
  # shape drifts over time. `gen_random_uuid()` is Postgres core (13+); UTC timestamps are
  # written with `timezone('UTC', now())` to match the `timestamp`-without-tz columns.

  def up do
    create table(:article_blocks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :article_id, references(:articles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :position, :integer, null: false, default: 0
      add :block_type, :string, null: false
      add :block_id, :binary_id, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:article_blocks, [:article_id, :position])

    alter table(:articles) do
      add :image_id, references(:media, type: :binary_id, on_delete: :nilify_all)
    end

    alter table(:thrones) do
      add :image_id, references(:media, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:articles, [:image_id])
    create index(:thrones, [:image_id])

    # --- Data backfill ------------------------------------------------------------

    # Hero row per article: the flagged use_as_article_image (unique per article), else
    # the first by sort/inserted_at — mirrors BbhWeb.Format.article_hero/1.
    execute """
    CREATE TEMP TABLE _hero ON COMMIT DROP AS
    SELECT article_id, id AS image_row_id, media_id FROM (
      SELECT ai.article_id, ai.id, ai.media_id,
        row_number() OVER (
          PARTITION BY ai.article_id
          ORDER BY ai.use_as_article_image DESC, ai.sort ASC NULLS LAST,
                   ai.inserted_at ASC, ai.id ASC
        ) AS rn
      FROM article_images ai
    ) t WHERE rn = 1
    """

    execute """
    UPDATE articles a SET image_id = h.media_id
    FROM _hero h WHERE h.article_id = a.id
    """

    # richtext block from a non-empty body (skip empty / bare "<p></p>").
    execute """
    CREATE TEMP TABLE _rt ON COMMIT DROP AS
    SELECT gen_random_uuid() AS block_id, a.id AS article_id, a.body
    FROM articles a
    WHERE a.body IS NOT NULL
      AND btrim(a.body) <> ''
      AND btrim(a.body) <> '<p></p>'
    """

    execute """
    INSERT INTO block_richtext (id, body, inserted_at, updated_at)
    SELECT block_id, body, timezone('UTC', now()), timezone('UTC', now()) FROM _rt
    """

    execute """
    INSERT INTO article_blocks (id, article_id, position, block_type, block_id, inserted_at, updated_at)
    SELECT gen_random_uuid(), article_id, 0, 'richtext', block_id,
           timezone('UTC', now()), timezone('UTC', now())
    FROM _rt
    """

    # grid gallery block from every non-hero image, in the editor's order.
    execute """
    CREATE TEMP TABLE _gal_src ON COMMIT DROP AS
    SELECT ai.article_id, ai.media_id,
      row_number() OVER (
        PARTITION BY ai.article_id
        ORDER BY ai.sort ASC NULLS LAST, ai.inserted_at ASC, ai.id ASC
      ) AS sort_rn
    FROM article_images ai
    JOIN _hero h ON h.article_id = ai.article_id
    WHERE ai.id <> h.image_row_id
    """

    # One gallery per article — collapse to distinct article_ids first, then assign a
    # single uuid each. `SELECT DISTINCT article_id, gen_random_uuid()` would not collapse:
    # the per-row uuid makes every row distinct, yielding one gallery per image.
    execute """
    CREATE TEMP TABLE _gal_block ON COMMIT DROP AS
    SELECT article_id, gen_random_uuid() AS gallery_id
    FROM (SELECT DISTINCT article_id FROM _gal_src) d
    """

    execute """
    INSERT INTO block_image_gallery (id, layout, lightbox, aspect_ratio, autoplay, inserted_at, updated_at)
    SELECT gallery_id, 'grid', true, '16:9', false,
           timezone('UTC', now()), timezone('UTC', now())
    FROM _gal_block
    """

    execute """
    INSERT INTO block_gallery_files (id, gallery_id, media_id, sort, inserted_at, updated_at)
    SELECT gen_random_uuid(), gb.gallery_id, gs.media_id, gs.sort_rn,
           timezone('UTC', now()), timezone('UTC', now())
    FROM _gal_src gs JOIN _gal_block gb ON gb.article_id = gs.article_id
    """

    execute """
    INSERT INTO article_blocks (id, article_id, position, block_type, block_id, inserted_at, updated_at)
    SELECT gen_random_uuid(), gb.article_id, 1, 'image_gallery', gb.gallery_id,
           timezone('UTC', now()), timezone('UTC', now())
    FROM _gal_block gb
    """

    # Throne picture: flagged use_as_throne_picture else first image — mirrors
    # throne_picture/1. Store it only when it differs from the article image; equal means
    # "inherit", left null.
    execute """
    CREATE TEMP TABLE _throne_pic ON COMMIT DROP AS
    SELECT article_id, media_id FROM (
      SELECT ai.article_id, ai.media_id,
        row_number() OVER (
          PARTITION BY ai.article_id
          ORDER BY ai.use_as_throne_picture DESC, ai.sort ASC NULLS LAST,
                   ai.inserted_at ASC, ai.id ASC
        ) AS rn
      FROM article_images ai
    ) t WHERE rn = 1
    """

    execute """
    UPDATE thrones th SET image_id = tp.media_id
    FROM _throne_pic tp
    JOIN articles a ON a.id = tp.article_id
    WHERE tp.article_id = th.article_id
      AND tp.media_id IS DISTINCT FROM a.image_id
    """
  end

  def down do
    # Remove only the blocks this migration created (referenced by article_blocks);
    # gallery files cascade from block_image_gallery. Pages' blocks are untouched.
    execute """
    DELETE FROM block_richtext
    WHERE id IN (SELECT block_id FROM article_blocks WHERE block_type = 'richtext')
    """

    execute """
    DELETE FROM block_image_gallery
    WHERE id IN (SELECT block_id FROM article_blocks WHERE block_type = 'image_gallery')
    """

    drop index(:thrones, [:image_id])
    drop index(:articles, [:image_id])

    alter table(:thrones) do
      remove :image_id
    end

    alter table(:articles) do
      remove :image_id
    end

    drop table(:article_blocks)
  end
end
