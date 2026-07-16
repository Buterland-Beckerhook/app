# Code Review: commit 7b25088 — article hero/preview-image/lightbox

Scope: logo-fallback hero, exclusive "preview image" switch, gallery lightbox
(new code only; pre-existing code noted one-line, not deep-analyzed).

## Summary
- **Status**: ⚠️ Changes Requested
- **Issues Found**: 5 new (0 critical, 3 warnings, 2 suggestions) + 1 note on adjacent pre-existing code

## Warnings

1. **lib/bbh/content.ex:139-150** — `set_article_preview_image/2` never bumps `updated_at` on
   `ArticleImage`; raw `update_all` bypasses changeset timestamps in both the clear-all and the
   set-one clause. CONFIRMED (verified: no `updated_at:` key in either `set:` list). Failure
   scenario: anything relying on `ArticleImage.updated_at` (ETag/cache invalidation, "last
   modified" UI, sync jobs) won't see the preview-image change. Fix: add
   `updated_at: DateTime.utc_now()` (or `NaiveDateTime.utc_now()`, matching the schema's
   timestamp type) to both `set:` keyword lists.

2. **lib/bbh/content.ex:141-146** — the clear-all `update_all` and the set-one `update_all` are
   two separate statements; only the second statement's affected-row `count` is checked. If
   `image_id` doesn't belong to `article_id` (bad/stale id from the client), the transaction still
   commits after having cleared every image's flag, then returns `{:error, :not_found}` — leaving
   the article with **zero** preview images instead of restoring the previous one. CONFIRMED via
   `Repo.transact` semantics (verified in `deps/ecto/lib/ecto/repo.ex` / `repo/transaction.ex`):
   returning `{:error, _}` from the function **rolls back** the whole transaction, so in practice
   this is safe — but only because `Repo.transact` (not `Repo.transaction`) is used. Flagging
   because this correctness depends entirely on that specific API choice; a future refactor to
   plain `Repo.transaction/1` (which does *not* auto-rollback on a returned `{:error, _}` tuple
   from inner code — only on `Repo.rollback/1`) would silently reintroduce the zero-preview-image
   bug. Consider a comment noting this invariant, or use `Repo.rollback/1` explicitly for clarity.

3. **lib/bbh_web/components/site_components.ex:14, 41, 79, 168** — `attr :article, :map` (also
   `:event`, `:people`) typed as generic `:map` rather than the actual struct. Pre-existing
   pattern, continued by the new `hero_image/1` attr. Loses attr-type documentation value.
   Suggestion-level.

## Suggestions

1. **lib/bbh_web/format.ex:60-64 + site_components.ex:20** — `article_hero/1` guards on
   `is_list(images)`; if `images` is `%Ecto.Association.NotLoaded{}` (preload missing at a call
   site), it falls through to `article_hero(_), do: nil` and `hero_image/1` silently renders the
   logo fallback instead of surfacing a missing-preload bug. PLAUSIBLE: any future caller of
   `<.hero_image article={...}>` that forgets `preload: [images: :media]` gets a "correct-looking"
   placeholder rather than a crash — easy to miss in review/QA. All current call sites
   (`article_card` fed from `list_published_articles/2`, `latest_articles/1`, `list_articles`;
   `show.html.heex` fed from `get_published_article/2`) do preload `images: :media`, so no live bug
   today. Consider asserting/logging on `%Ecto.Association.NotLoaded{}` in dev/test.

2. **lib/bbh_web/controllers/article_html/show.html.heex:24,38** — `hero = article_hero(@article)`
   (line 24) is computed via `<% %>` solely to exclude it from the gallery at line 38, while
   `<.hero_image>` (line 25) independently recomputes `article_hero/1` again internally. Not dead
   code — both uses are load-bearing — but it's a redundant duplicate call (harmless: pure
   function over an already-loaded, typically small list). Consider a short comment noting the
   duplication is intentional, or thread the computed hero into the component via an attr.

## Adjacent pre-existing code (not deep-analyzed)
- `lib/bbh_web/live/admin/article_live/form.ex:82-84` — on `{:error, _}` from
  `set_article_preview_image`, `reload_images/1` is NOT called, so `@images` stays stale if the
  failure was due to concurrent deletion of that image; minor UX inconsistency, not a data
  bug (Content is source of truth).

## Clean
- `Repo.transact/1` usage (content.ex:140) confirmed correct against `deps/ecto/lib/ecto/repo.ex`:
  wraps in a DB transaction, unwraps `{:ok, _}`/`{:error, _}` directly, auto-rollback on returned
  `{:error, _}`. Matches the `{:ok, image_id} | {:error, :not_found}` handling in
  `form.ex:78-84`.
- `media_url(_, width: nil, height: nil)` path (format.ex:44-57) correctly produces the bare
  `/media/#{key}` URL — both nil opts are filtered out before `URI.encode_query`.
- `hero_image/1` HEEx (`:if={@hero}` / `:if={!@hero}`) is idiomatic and mutually exclusive; logo
  fallback correctly uses `object-contain` vs. `object-cover` for real images.
- Lightbox JS (assets/js/app.js:66-96) is a reasonable, dependency-free delegated-click
  implementation using native `<dialog>`; no XSS concern since `src`/`alt` values originate from
  HEEx-escaped server-rendered attributes.
- `img_id` param in `set_preview_image` LiveView event (a string from `phx-value-img_id`) is
  passed straight into the Ecto query (`i.id == ^image_id`); Ecto casts it via the query's typed
  parameter, no manual `String.to_integer` needed — correct as-is.
