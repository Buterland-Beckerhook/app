# Triage — feat/phoenix-rewrite

Source: `phoenix-rewrite-review.md` · Triaged interactively.
**17 to fix · 1 skipped · deferred items listed at bottom.**

User approach decisions (apply during fixes):
- **DB SSL** → document as accepted risk (internal Docker network), don't enable TLS.
- **Rate limiting** → add **Hammer** dependency, use for all four endpoints.
- **Trix sanitization** → add **HtmlSanitizeEx**, sanitize `@body` on save (changeset).

---

## Fix Queue

### BLOCKERs
- [ ] **thrones on_delete** — `migrations/...150853_create_articles_images_thrones.exs:56-57` —
      change `on_delete: :nilify_all` → `:delete_all` (keep `null: false`). Article delete currently crashes.
- [ ] **Health endpoints** — add liveness (always-200) + readiness (`SELECT 1`) plug/routes;
      wire `healthcheck:` into `deploy/compose.yml` phoenix service + `health_uri` into `deploy/Caddyfile`;
      add `paths: ["/health"]` to `config.exs` `force_ssl` exclude so internal HTTP checks aren't redirected.
- [ ] **Graceful shutdown** — `stop_grace_period: 60s` on phoenix service + endpoint Bandit drain/`shutdown_timeout`.
- [ ] **DB SSL** — `runtime.exs:52` — leave off, replace commented line with a clear comment documenting
      it as an accepted risk on the internal Compose network. *(per decision)*
- [ ] **PHX_HOST** — `runtime.exs:74` — `|| raise "PHX_HOST is required"` instead of defaulting to `example.com`.

### Security (all WARNINGs)
- [ ] **Push API** — `api/push_controller.ex` + `notifications.ex:14` — authn/throttle `subscribe`,
      cap rows; in `notify/2` require https + push-service host allowlist (SSRF guard).
- [ ] **TOTP sudo mode** — `live/user_live/totp.ex:44,53` — add `on_mount {BbhWeb.UserAuth, :require_sudo_mode}`.
- [ ] **Rate limiting (Hammer)** — TOTP challenge (`totp_controller.ex:12`), password login
      (`login.ex:106-125`), magic-link (`user_session_controller.ex:31`), push subscribe. *(add Hammer dep)*
- [ ] **Altcha replay** — `altcha.ex:32-47` — embed+verify expiry in signed challenge; record used
      challenges in short-TTL cache to reject replays; bound `number` by `maxnumber`.
- [ ] **Upload safety** — `media/upload.ex` + `media.ex:78-106` — validate magic bytes (not client
      type); serve `.svg` with `Content-Disposition: attachment` (or sanitize).
- [ ] **CSP header** — `endpoint.ex`/router — add Content-Security-Policy via `put_secure_browser_headers/2`.
- [ ] **Sanitize Trix body (HtmlSanitizeEx)** — sanitize `@body` on save in article/event/page-block
      changesets; keeps `show.html.heex` / `site_components.ex` `raw/1` safe. *(add HtmlSanitizeEx dep)*

### Ecto & correctness
- [ ] **Swallowed failures** — `contact_controller.ex:18` (branch on mailer `{:ok}`/`{:error}`, log on error)
      + `content.ex move_block/3` (propagate `Repo.transaction` result instead of always `:ok`).
- [ ] **Ecto constraints/indexes** —
      add FK indexes: `people.portrait_id`, `events.location_id`, `events.image_id`, `images.media_id`,
      `block_media_card.image_id`, `block_gallery_files.media_id`;
      add `foreign_key_constraint`: `Event.image_id`, `Person.portrait_id`, `MediaCard.image_id`,
      `GalleryFile.gallery_id`/`media_id`;
      mirror check constraints with `check_constraint/3`: `articles_year_range`, `events_year_range`,
      `people_sort_order_nonneg`, `users_role_valid`.
- [ ] **Verify preload** — `event_live/index.ex:33` reads `e.location.name` per row — confirm
      `Calendar.list_events()` preloads `:location` (fix if N+1).

### Tests
- [ ] **Coverage** — add tests for all `bbh_web/live/admin/**` LiveViews (mount/render/handle_event/authz),
      `user_live/totp.ex`, public controllers (article/event/contact+altcha/media/page_content/sitemap/
      throne/totp/api-push), and contexts `Bbh.Media` / `Bbh.Notifications` / `Bbh.Contact` (+ fixtures).
      Add `setup :register_and_log_in_admin` helper first.
- [ ] **async: true** — `accounts_test.exs:2`, `page_controller_test.exs:2`.

### LiveView improvements
- [ ] **Streams** — convert `media_live/index.ex` (and ideally other admin index views) to `stream/3`
      + `stream_insert`/`stream_delete`.
- [ ] **assign_async** — `dashboard_live.ex` (4 sync queries in mount); `article_live/form.ex` media picker.
- [ ] **Task.Supervisor** — replace unsupervised `Task.start/1` in `article_live/form.ex:150` /
      `event_live/form.ex:92` with supervised tasks.
- [ ] **Self-role guard** — `admin/user_live/index.ex` `set_role` — add self-guard like `delete` has;
      also block demoting the last admin.

---

## Skipped (intentional, no change)
- `content.ex:48` `list_thrones` `per_page: 1` — **intentional**: only one throne is shown per page.

## Deferred (SUGGESTION-level, revisit later)
- Security nits: `Path.safe_relative/2` for media guard; strip CR/LF from contact `name`; TOTP `:since` window.
- Ecto nits: composite `images (article_id, sort)` index; `thrones (begin_year desc)` index; escape `_` in
  `filter_search`; `:decimal` for lat/lng/focal_point; unique constraint backing `MAX+1` ordinals.
- Deploy warnings: Caddy `tls` ACME email + extra headers; `backup.sh` volume-name/`COMPOSE_PROJECT_NAME`
  check + dump-integrity verify; document `POOL_SIZE`/`ECTO_IPV6`/`DNS_CLUSTER_QUERY` in `.env.example`;
  JSON logging + error tracking (Sentry/AppSignal); dedicated migration-safety review.
- Idiom nits: narrow blanket rescues (`altcha.ex`, `notifications.ex send_one/2`); `bbh.import.ex:24`
  `app.start` → `app.config`; `page_content_controller.ex verein_page` cond→pattern-match; granular
  error atoms in `accounts.ex update_user_email/2`.

## Open question (needs your call)
- Admin `handle_event`s skip per-action authorization (flat editor/admin role model), gated only at
  mount by `require_admin`. Confirm this flat model is intended (no per-resource ownership checks).
