# Ecto Review — feat/phoenix-rewrite

No Ash Framework detected (`grep -rE "ash_postgres|use Ash.Resource" app/mix.exs app/lib` returned nothing). Ecto patterns apply.

## BLOCKER

- `app/priv/repo/migrations/20260713150853_create_articles_images_thrones.exs:56-57` — `thrones.article_id` is declared `null: false` **and** `on_delete: :nilify_all`. If the parent article is deleted, Postgres will try to set `article_id` to NULL, which violates the NOT NULL constraint and raises a hard DB error (delete fails ungracefully) instead of the intended cascade. — **Why**: contradictory FK config; `Content.delete_article/1` will crash for any article that has a throne. — **Fix**: change to `on_delete: :delete_all` (a throne has no meaning without its article — matches `unique_index(:thrones, [:article_id])` has_one semantics) or drop `null: false` if orphaned thrones are intended.

## WARNING

- `app/priv/repo/migrations/20260713150852_create_people.exs:17`, `...150854_create_events.exs:22,24`, `...150853...:38 (images.media_id)`, `...150855_create_pages_and_blocks.exs:38,56` — FK columns `people.portrait_id`, `events.location_id`, `events.image_id`, `images.media_id`, `block_media_card.image_id`, `block_gallery_files.media_id` have no index. — **Why**: every FK used in a JOIN/lookup or that has `on_delete` cascading behavior should be indexed to avoid seq scans on lookups and slow cascade deletes. `events.parent_id`/`article_id` (thrones)/`gallery_id` are correctly indexed; these are not. — **Fix**: `create index(:people, [:portrait_id])`, `create index(:events, [:location_id])`, `create index(:events, [:image_id])`, `create index(:images, [:media_id])`, `create index(:block_media_card, [:image_id])`, `create index(:block_gallery_files, [:media_id])`.

- `app/lib/bbh/calendar/event.ex:37-67` — `image_id` is castable but `changeset/2` never calls `foreign_key_constraint(:image_id)` (unlike `:location_id` and `:parent_id`, which do). — **Why**: an invalid/stale `image_id` will raise an unhandled `Ecto.ConstraintError` instead of a changeset error. — **Fix**: add `|> foreign_key_constraint(:image_id)`.

- `app/lib/bbh/club/person.ex:50-69` — `portrait_id` is cast but no `foreign_key_constraint(:portrait_id)`. Same gap in `app/lib/bbh/content/blocks.ex:71-75` (`MediaCard.image_id`) and `:113-115` (`GalleryFile` has `validate_required` but no `foreign_key_constraint` for `gallery_id`/`media_id`). — **Why**: race-condition safety (Iron Law #6) — validations alone don't protect against concurrent deletes of the referenced row. — **Fix**: add `foreign_key_constraint/2` calls for each castable FK.

- `app/lib/bbh/content/article.ex:44-48`, `app/lib/bbh/calendar/event.ex:55-63`, `app/lib/bbh/club/person.ex:66-68` — DB-level `check` constraints exist (`articles_year_range`, `events_year_range`, `people_sort_order_nonneg`) but the changesets only call `validate_number`, never `check_constraint/3` for these names. — **Why**: if the app-level validation is bypassed or a race occurs, the DB constraint violation surfaces as a raw Postgrex error instead of a friendly changeset error. — **Fix**: add matching `check_constraint(:year, name: :articles_year_range)` / `:events_year_range` / `check_constraint(:sort_order, name: :people_sort_order_nonneg)`.

- `app/lib/bbh/content/page_block.ex` + `app/priv/repo/migrations/20260713150855_create_pages_and_blocks.exs:77-85` — `page_blocks.block_id` is a Rails-style polymorphic FK (`block_type` + `block_id` with no DB reference), explicitly called out in the migration comment as "integrity enforced in the app layer." This is exactly the anti-pattern in Iron Law #3. — **Why**: nothing at the DB level prevents a dangling `block_id` if a concrete block row is ever deleted outside `Bbh.Content.delete_block/1`/`delete_page/1` (e.g., manual query, future code path, or a bug in `move_block/3`). — **Fix**: acceptable as a deliberate, documented trade-off given block tables are heterogeneous, but consider a background integrity check job or restricting all deletes to the context functions (no other Repo.delete call-sites on block schemas exist today — verified).

- `app/lib/bbh/content.ex:48` — `list_thrones(page \\ 1, per_page \\ 1)` defaults `per_page` to **1**. — **Why**: looks like an unintentional default (every other paginator defaults to 10); a caller relying on the default gets a single throne per page. — **Fix**: confirm intent; likely should default to 10 like `list_published_articles/2`.

- `app/lib/bbh/club/person.ex` — `birth_date`/`death_date` stored as free-form `:string` rather than `:date`. — **Why**: no format validation, can't be sorted/filtered/compared reliably. May be intentional (partial/approximate historical dates), but worth confirming.

## SUGGESTION

- `app/priv/repo/migrations/20260713150853_create_articles_images_thrones.exs:50` — `images` indexed only on `article_id`; `ArticleImage` queries always order by `sort` (`app/lib/bbh/content.ex:110-117`). Consider composite `[:article_id, :sort]`.
- `app/priv/repo/migrations/20260713150853...:76` — `thrones` indexed on `[:type, :begin]`, but `current_throne/0` and `list_thrones/2` order by `begin_year` without filtering `:type`; a plain index on `[:begin]` (desc) would serve those queries better.
- `app/lib/bbh/content.ex:180-193, 137-141, 231-234` (`add_block/2`, `next_image_sort/1`, `next_position/2`) — position/sort computed via `MAX(...) + 1` with no unique DB constraint on `(page_id, position)` or `(article_id, sort)`; concurrent admin edits could produce duplicate ordinals. Low risk given single-admin-at-a-time usage, but a unique index would make this race-proof per Iron Law #6.
- `app/lib/bbh/media.ex:36-39` — `filter_search/2` escapes `%` in the ilike pattern but not `_`, so a literal underscore in a search term acts as a wildcard. Minor, not a security issue.
- `app/lib/bbh/calendar/location.ex:11-12` and `media/upload.ex:12-13` — `lat`/`lng`/`focal_point_x/y` as `:float`. Not money, so not an Iron Law violation, but `:decimal` would avoid floating-point drift if these are ever used in equality comparisons.
- `app/priv/repo/migrations/20260713155257_add_role_and_totp_to_users.exs:12` — DB check `users_role_valid` has no matching `check_constraint(:role, ...)` in `User.role_changeset/2` (only `validate_inclusion`). Same pattern as the year/sort_order gap above.

## What looks good

- All tables use `:binary_id` PKs/FKs and `utc_datetime` timestamps consistently via `Bbh.Schema`.
- `has_many` associations are loaded via separate preload queries (not joins) throughout `Bbh.Content`/`Bbh.Calendar`/`Bbh.Club` — correct per Iron Law #7; `Content.load_blocks/1` batches polymorphic child loads by type to avoid N+1.
- Composite unique/lookup indexes (`articles_slug_year_unique`, `events_slug_year_unique`, `(status, slug, year)`, `(status, announce, start)`) line up well with the actual `WHERE`/`ORDER BY` clauses in `Bbh.Calendar`/`Bbh.Content`.
- No money fields; no floats used for anything monetary.
- `unsafe_validate_unique` + `unique_constraint` pairing on `User.email_changeset/3` is correct (Iron Law #6).
- Migrations are all reversible (`def change` with reversible operations only).
