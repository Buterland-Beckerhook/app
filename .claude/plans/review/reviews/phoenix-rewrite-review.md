# Review — feat/phoenix-rewrite (Directus+SvelteKit → Elixir+Phoenix)

**Verdict: REQUIRES CHANGES**

Reviewed the full rewrite branch (164 changed files) with 8 parallel specialists:
Elixir idioms, security, tests, LiveView, Ecto, deployment, Iron Laws, verification.

Verification baseline is green: `mix compile --warnings-as-errors`, `mix format
--check-formatted`, and **132 tests all pass**. (No credo/dialyzer/sobelow configured.)

The foundation is clean and idiomatic — thin controllers, contexts own their queries,
solid `phx.gen.auth` base (Argon2, timing-safe checks, session fixation handled, CSRF,
force_ssl/HSTS, env secrets, parameterized queries). What blocks a merge is **one
data-integrity bug**, a cluster of **security hardening gaps** on new endpoints, **four
production-readiness deployment gaps**, and **large test-coverage holes** in the new
admin/public surface.

---

## BLOCKER (1)

1. **`app/priv/repo/migrations/20260713150853_create_articles_images_thrones.exs:56-57`**
   — `thrones.article_id` is `null: false` **and** `on_delete: :nilify_all`. Deleting an
   article that has a throne makes Postgres set `article_id = NULL`, violating NOT NULL →
   `Content.delete_article/1` crashes with a raw DB error instead of cascading.
   **Fix:** change to `on_delete: :delete_all` (a throne has no meaning without its article;
   matches the `unique_index(:thrones, [:article_id])` has_one semantics).

---

## Security — WARNINGs

- **`controllers/api/push_controller.ex` + `notifications.ex:14`** — `POST /api/push/subscribe`
  is unauthenticated and unthrottled (table flooding), and `notify/2` later POSTs to the
  client-supplied `endpoint` → **SSRF** to internal hosts; `unsubscribe` removes any known
  endpoint. Rate-limit, require https + push-service host allowlist, cap rows.
- **`live/user_live/totp.ex:44,53`** — enabling/**disabling** TOTP needs only a session, not
  sudo mode (password/email changes DO require sudo). A stolen session can strip 2FA. Add
  `on_mount {BbhWeb.UserAuth, :require_sudo_mode}`.
- **`controllers/totp_controller.ex:12`** — no throttling on the 6-digit TOTP challenge →
  brute-forceable once first factor known. Rate-limit per pending user/IP; lock after N fails.
  *(also flagged by iron-law-judge)*
- **`live/user_live/login.ex:106-125` + `user_session_controller.ex:31`** — no rate limiting on
  password login / magic-link → brute force + email-bombing. Add per-IP+email limit (Hammer).
- **`bbh/altcha.ex:32-47`** — challenge has no expiry/nonce store; a valid PoW payload is
  **infinitely replayable**, so `/kontakt` spam protection is bypassable. Embed+verify an
  expiry and record used challenges (short-TTL cache).
- **`media/upload.ex` + `media.ex:78-106`** — uploads trust client extension/type, no magic-byte
  check; `.svg` served inline as `image/svg+xml` from app origin → **stored-XSS surface**.
  Validate magic bytes; force `Content-Disposition: attachment` for SVG (or sanitize).
- **`endpoint.ex` / router** — no **Content-Security-Policy** header, despite serving user media
  and Trix rich content. Add a CSP via `put_secure_browser_headers/2`.
- **`article_html/show.html.heex:33`, `event_html/show.html.heex:45`, `site_components.ex:183,190,214`**
  — Trix-authored `@body` rendered with `raw/1` and no server-side sanitizer anywhere. Admin/editor
  authored (lower risk than anonymous XSS) but no defense-in-depth. Sanitize on save
  (`HtmlSanitizeEx`). *(the `totp.ex:85 raw(@qr)` is fine — server-generated SVG.)*

### Security — SUGGESTIONs
- `media.ex:151` prefer `Path.safe_relative/2` over the `String.contains?("..")` blocklist.
  *(also iron-law)*
- `contact.ex:40-41` strip CR/LF from `name` before it goes into mail subject/reply-to.
- `admin/user_live/index.ex` — no guard against an admin demoting the last admin (self-lockout);
  `set_role` also lacks the self-guard that `delete` has. *(also liveview, iron-law)*
- TOTP `NimbleTOTP.valid?` without `:since` → code reusable within its 30s window.
- `runtime.exs:53` DB `ssl: true` commented out (see deployment).

---

## Deployment — BLOCKERs (pre-production)

- **No health-check endpoints anywhere** — no `/health/*` routes, no health plug, no
  `healthcheck:` on the `phoenix` compose service, no Caddy `health_uri`. Caddy will route to a
  booting/broken instance. Add liveness (always-200) + readiness (`SELECT 1`), wire into compose
  + Caddyfile.
- **No graceful shutdown** — no `stop_grace_period` on `phoenix` (Docker default ~10s) and no
  Bandit drain config → in-flight requests + LiveView sockets killed on every deploy. Set
  `stop_grace_period: 60s` + endpoint `shutdown_timeout`.
- **`runtime.exs:52` DB SSL fully disabled** (`# ssl: true` commented out) — no encryption
  phoenix↔postgres. Enable with `verify: :verify_peer`, or explicitly document as accepted risk
  on the internal bridge network.
- **`runtime.exs:74` `PHX_HOST` silently defaults to `"example.com"`** instead of raising like
  `DATABASE_URL`/`SECRET_KEY_BASE` → silently breaks URL generation, emails, sitemap, host checks.
  Change to `|| raise "PHX_HOST is required"`.

### Deployment — WARNINGs
- `Caddyfile` — no explicit `tls` (ACME email) or extra security headers.
- `config.exs` `force_ssl` exclude has no `paths: ["/health"]` (add once health routes exist, so
  plain-HTTP internal healthchecks aren't redirected).
- `backup.sh:20` hardcodes volume `bbh_uploads` — only matches if `COMPOSE_PROJECT_NAME=bbh`
  (dir is `deploy`); verify or the backup silently archives nothing. `:14` add dump-integrity
  check before pruning old backups.
- `.env.example` doesn't document `POOL_SIZE`/`ECTO_IPV6`/`DNS_CLUSTER_QUERY`.
- No structured (JSON) logging, no error tracking (Sentry/AppSignal).
- Migrations not inspected for safety in this pass — recommend a dedicated migration-safety review.

---

## Ecto — WARNINGs
- **Missing FK indexes:** `people.portrait_id`, `events.location_id`, `events.image_id`,
  `images.media_id`, `block_media_card.image_id`, `block_gallery_files.media_id`.
- **Missing `foreign_key_constraint`** in changesets: `Event.image_id`, `Person.portrait_id`,
  `MediaCard.image_id`, `GalleryFile.gallery_id`/`media_id` → stale FK raises `Ecto.ConstraintError`
  instead of a changeset error.
- **DB check constraints not mirrored** with `check_constraint/3`: `articles_year_range`,
  `events_year_range`, `people_sort_order_nonneg`, `users_role_valid` → races surface as raw
  Postgrex errors.
- **`content.ex:48` `list_thrones(page \\ 1, per_page \\ 1)`** — `per_page` defaults to **1**
  (every other paginator defaults to 10); likely a typo.
- `page_blocks` polymorphic FK (`block_type`+`block_id`, no DB reference) — documented deliberate
  trade-off; consider restricting all block deletes to context functions.
- `Person.birth_date`/`death_date` stored as free-text `:string` not `:date` — confirm intent
  (may be intentional for partial historical dates).

### Ecto — SUGGESTIONs
- Composite index `images (article_id, sort)`; a `thrones (begin_year desc)` index for
  `current_throne/0`/`list_thrones/2`.
- `add_block`/`next_image_sort`/`next_position` compute ordinals via `MAX+1` with no unique
  constraint → duplicate ordinals under concurrent edits (low risk, single-admin). *(also elixir)*
- `media.ex:36-39` `filter_search` escapes `%` but not `_`.
- `lat`/`lng`/`focal_point` as `:float` — `:decimal` avoids drift if ever compared for equality.

**Good:** consistent `binary_id`/`utc_datetime` via `Bbh.Schema`, `has_many` loaded via separate
preloads (no N+1), `Content.load_blocks/1` batches polymorphic children, composite indexes match
query patterns, `unsafe_validate_unique` + `unique_constraint` on email, all migrations reversible.

---

## Elixir idioms / Iron Laws — WARNINGs
- **`contact_controller.ex:18`** — `_ = Bbh.Contact.deliver(data)` discards the mailer result;
  a failed delivery still shows the user a success flash with no log trail. Branch on
  `{:ok,_}`/`{:error,_}`. *(elixir + iron-law)*
- **`content.ex` `move_block/3` (~208-223)** — discards the `Repo.transaction` result and always
  returns `:ok`; a failed admin block-reorder looks identical to success. Propagate `{:ok,_}`/`{:error,_}`.
- **`altcha.ex:32-47` `verify/1`** — blanket `rescue _ -> false` over an already-exhaustive
  `with/else` can mask real bugs (e.g. HMAC misconfig) as ordinary verification failures. Narrow
  the rescue or log before returning false.
- **`mix/tasks/bbh.import.ex:24`** — `Mix.Task.run("app.start")` boots the full endpoint for a
  one-off import; use `app.config` + `ensure_all_started`. Low impact (throwaway task).

### Iron Laws / LiveView — SUGGESTIONs
- All admin `index/dashboard` LiveViews load DB data unconditionally in `mount/3` (no
  `connected?`/`assign_async`) → 2× query per view. Low impact (auth-gated, small lists);
  `dashboard_live.ex` runs 4 queries — best `assign_async` candidate.
- Admin index views use `assign` on collections though `<.table>` is stream-ready; migrate to
  `stream/3`, most importantly `media_live/index.ex` (image library grows unbounded).
- `article_live/form.ex:150` / `event_live/form.ex:92` fire notifications via unsupervised
  `Task.start/1` — use `Task.Supervisor` for crash visibility.
- `notifications.ex send_one/2` — narrow the whole-function `rescue` to just the HTTP call so a
  `Repo` error isn't logged as a "web push error".
- **Confirm:** admin `handle_event`s intentionally skip per-action authz (flat editor/admin role
  model) — mount-level `require_admin` gating is otherwise correct.
- **Verify N+1:** `event_live/index.ex:33` reads `e.location.name` per row — confirm
  `Calendar.list_events()` preloads `:location`.

---

## Tests — coverage gaps (drives the verdict)
- **Two `async: true` omissions:** `accounts_test.exs:2` (WARNING — largest file, serializes
  needlessly; siblings all use `async: true`), `page_controller_test.exs:2`.
- **Zero tests** for a large new surface:
  - all `bbh_web/live/admin/**` LiveViews (article/event/location/media/page/person/user CRUD +
    dashboard) — mount/render, `handle_event` save/delete/validate, and authorization all unverified.
  - `user_live/totp.ex`.
  - public controllers: `article`, `event`, `contact` (incl. altcha integration), `media`,
    `page_content`, `sitemap`, `throne`, `totp`, `api/push`.
  - new contexts: `Bbh.Media`, `Bbh.Notifications`, `Bbh.Contact` (no fixtures either).
- Existing tests are otherwise solid: correct sandbox isolation, pattern-matching assertions, no
  `Process.sleep`, no over-mocking. Suggest adding `setup :register_and_log_in_admin` before
  writing admin LiveView tests.

**Good:** no flaky patterns, `altcha_test.exs` correctly documents its `async: false`.

---

## Deconfliction notes
Merged cross-agent duplicates: contact-mailer result (elixir+iron-law), import task boot
(elixir+iron-law), TOTP rate-limiting (security+iron-law), path-traversal guard (security+iron-law),
`user_live` self-role guard (liveview+iron-law+security), ordinal race (elixir+ecto), streams/mount
(liveview+iron-law). "Unconditional DB in mount" and "streams" demoted to SUGGESTION given the small
auth-gated admin dataset.
