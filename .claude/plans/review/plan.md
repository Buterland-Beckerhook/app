# Plan — feat/phoenix-rewrite review fixes

**Source:** `.claude/plans/review/reviews/review-triage.md` · **Branch:** `feat/phoenix-rewrite`
**Scope:** 17 approved fix items → 30 tasks across 7 phases. Every triaged finding maps to a task
below or is listed under *Deferred / Skipped*.

## Decisions locked in
- **DB SSL** → keep off, document as accepted risk (internal Docker network).
- **Rate limiting** → add `hammer`, one shared limiter module.
- **Trix HTML** → add `html_sanitize_ex`, sanitize on save.
- **`list_thrones per_page: 1`** → intentional, no change.
- **Admin authz** → assumed flat editor/admin model (mount-level `require_admin` sufficient).

Verification after every phase: `mix compile --warnings-as-errors && mix format && mix test`.

---

## Phase 0 — Dependencies & test scaffolding
- [x] Add `{:hammer, "~> 7.0"}` and `{:html_sanitize_ex, "~> 1.4"}` to `app/mix.exs`; `mix deps.get`. — hammer 7.1, html_sanitize_ex 1.4; compiles clean. (Pre-existing earmark retired/vuln, out of scope.)
- [x] `[test]` Add `setup :register_and_log_in_admin` helper in `test/support/conn_case.ex`
      (registers a user with the admin role + logs in) — prerequisite for admin LiveView tests. — added `admin_user_fixture/1` to accounts_fixtures + helper using it.
- [x] Configure Hammer backend (ETS) in `application.ex` supervision tree + `config.exs`. — `{BbhWeb.RateLimit, clean_period: 10min}` child; `enabled: true` in config.exs, `false` in test.exs; boot check :ok.

## Phase 1 — Data integrity `[ecto]`
> Migrations edited in place (not yet deployed) + `mix ecto.reset`. If already migrated anywhere,
> switch to a new alter-migration instead.
- [x] **BLOCKER** `migrations/...150853_create_articles_images_thrones.exs:56-57` —
      `on_delete: :nilify_all` → `:delete_all` (keep `null: false`). — thrones.article_id now :delete_all.
- [x] Add FK indexes: `people.portrait_id` (`...150852`), `events.location_id`+`image_id` (`...150854`),
      `images.media_id` (`...150853`), `block_media_card.image_id`+`block_gallery_files.media_id` (`...150855`). — all 6 added.
- [x] Add `foreign_key_constraint/2` in changesets: `Event.image_id` (`calendar/event.ex`),
      `Person.portrait_id` (`club/person.ex`), `MediaCard.image_id` + `GalleryFile.gallery_id`/`media_id`
      (`content/blocks.ex`). — done (Event location/parent already had them).
- [x] Add `check_constraint/3` mirrors: `articles_year_range` (`content/article.ex`),
      `events_year_range` (`calendar/event.ex`), `people_sort_order_nonneg` (`club/person.ex`),
      `users_role_valid` (`accounts/user.ex` `role_changeset`). — all 4 mirror existing DB constraints.
- [x] Verify `Calendar.list_events/0` preloads `:location` (fixes potential N+1 at `event_live/index.ex:33`). — already preloads `[:location]`; no change.
- [x] `mix ecto.reset` + run tests to confirm schema/changeset changes are green. — test DB rebuilt migration-only (seeds pollute test DB; do NOT seed test DB), 60 ctx tests green. Dev `ecto.reset` blocked by active dev-server sessions; applies on next reset.

## Phase 2 — Deployment hardening
- [x] `[phoenix]` Add health plug + routes: `/health/liveness` (always 200),
      `/health/readiness` (`SELECT 1` via `Ecto.Adapters.SQL.query`), mounted before the router in `endpoint.ex`. — `BbhWeb.Plugs.Health`; behavioral check liveness=200 readiness=200.
- [x] `deploy/compose.yml` — add `healthcheck:` to the `phoenix` service hitting `/health/liveness`. — curl-based (added curl to Dockerfile runner), 15s/5s/5retries/30s start.
- [x] `deploy/Caddyfile` — add `health_uri`/`health_port` to the `reverse_proxy` block. — health_uri /health/liveness + interval/timeout; health_port omitted (upstream already :4000).
- [x] `config/config.exs` — add `paths: ["/health"]` to `force_ssl` exclude. — N/A: no `force_ssl` configured anywhere; TLS terminates at the proxy (Traefik/Caddy), app serves plain HTTP internally (confirmed by user). No exclusion needed.
- [x] Graceful shutdown: `stop_grace_period: 60s` on phoenix service (`compose.yml`) +
      endpoint Bandit `http: [..., shutdown_timeout: ...]` / drainer in `endpoint.ex`. — Bandit drains built-in (drainer is Cowboy-only); set `thousand_island_options: [shutdown_timeout: 55_000]` in runtime.exs + `stop_grace_period: 60s`.
- [x] `config/runtime.exs:52` — replace commented `# ssl: true` with a comment documenting SSL is
      intentionally off on the internal Compose network (accepted risk). — done.
- [x] `config/runtime.exs:74` — `PHX_HOST` → `|| raise "PHX_HOST is required"`. — done.

## Phase 3 — Security `[security]`
- [x] Create `BbhWeb.RateLimit` (Hammer wrapper) with per-IP+key check/increment helpers. — `use Hammer, backend: :ets`; `check/4` → `:ok` | `{:error, retry_after_ms}`, disabled in test. (Built in Phase 0.)
- [x] Apply rate limit: TOTP challenge (`totp_controller.ex:12`), password login
      (`user_live/login.ex`), magic-link (`user_session_controller.ex:31`), push subscribe. — TOTP verify + password login + magic-link login (10/5min) in controllers; magic-link email send (5/15min) in login.ex (added :peer_data/:x_headers to LiveSocket connect_info, `client_ip/1` helper). Push subscribe rate-limit applied in P3-T5.
- [x] `user_live/totp.ex` — add `on_mount {BbhWeb.UserAuth, :require_sudo_mode}` (enable + disable). — module-level on_mount; stacks after live_session require_authenticated.
- [x] `bbh/altcha.ex` — embed+verify an expiry in the signed challenge; record used challenges in a
      short-TTL cache (ETS/Cachex) to reject replays; bound solution by `maxnumber`. — expiry in salt (signature-bound, 300s TTL), `number` bounded 0..maxnumber, `Bbh.Altcha.ReplayCache` (ETS GenServer, insert_new) rejects replays. Behavioral: valid=true, replay=false, tampered=false.
- [x] Push API `api/push_controller.ex` + `notifications.ex` — throttle/authn `subscribe`, cap rows;
      in `notify/2` require `https` + push-service host allowlist (SSRF guard) before POST. — subscribe rate-limited (20/min/IP), row cap 10k (new rows only), `valid_push_endpoint?/1` (https + FCM/Apple/Mozilla/WNS allowlist) enforced at subscribe AND before each send (prunes bogus rows).
- [x] Uploads `media/upload.ex` + `media.ex` — validate magic bytes (not client type); serve `.svg`
      with `Content-Disposition: attachment`. — `store_file` sniffs magic bytes (jpeg/png/gif/webp/avif/svg), rejects spoofed files ({:error, :unsupported_media_type}), derives ext+content_type from bytes; media_controller sets `content-disposition: attachment` for svg; media_live save handler reports rejections. Patterns verified standalone.
- [x] CSP — add `content-security-policy` via `put_secure_browser_headers/2` in `router.ex` browser pipeline. — `BbhWeb.Plugs.CSP` (per-request nonce + `strict-dynamic`), threaded nonce into app.js/theme/matomo scripts; img-src allows blob: (upload previews); Matomo origin added to script/connect/img when configured; disabled in dev (LiveReload). Header verified.
- [x] Trix sanitization — sanitize `@body` on save (`HtmlSanitizeEx`) in article/event/page-block
      changesets; keep `raw/1` render sites unchanged (now safe). Backfill note: existing rows unaffected
      pre-deploy (fresh DB). — `Bbh.Html.sanitize/1` (basic_html) via `update_change(:body,...)` in Article, Event, RichText, Alert, MediaCard changesets. Verified: keeps h1/strong/a, drops script + onerror. All 132 tests green.

## Phase 4 — Correctness
- [x] `contact_controller.ex:18` — branch on `Bbh.Contact.deliver/1` result; `Logger.error` +
      user-facing error flash on `{:error, _}`. — done; re-renders form with error flash on delivery failure.
- [x] `content.ex move_block/3` — propagate `Repo.transaction` result (`{:ok,_}`/`{:error,_}`); update
      the calling LiveView `handle_event` to flash on failure. — returns transaction result / `{:ok, :noop}` at edges; page_live/form handle_event flashes on `{:error,_}`.

## Phase 5 — LiveView improvements `[liveview]`
- [x] `media_live/index.ex` — convert to `stream/3` + `stream_insert`/`stream_delete` on upload/delete;
      switch `<.table rows={@streams.items}>`. — already stream-based (grid via `phx-update="stream"` over `@streams.items`); no change needed.
- [x] `dashboard_live.ex` — move the 4 mount queries into `assign_async`;
      `article_live/form.ex` — `assign_async` the media-picker list. — dashboard `assign_async(:stats,…)` + `<.async_result>` (skeleton/failed slots); article form `assign_async(:media_library,…)` in edit mount + search_media handler, picker grid wrapped in `<.async_result>`.
- [x] Replace unsupervised `Task.start/1` (`article_live/form.ex:150`, `event_live/form.ex:92`) with
      `Task.Supervisor.start_child/2` under the app supervision tree. — both already use `Task.Supervisor.start_child(Bbh.TaskSupervisor,…)`; supervisor present in `application.ex:17`.
- [x] `admin/user_live/index.ex` — add self-guard to `set_role` (mirror `delete`); block demoting the
      last remaining admin. — already implemented (`set_role` cond: self-guard + `demoting_last_admin?/2` via `count_admins/0`).

## Phase 6 — Tests `[test]`
- [x] `async: true` — `accounts_test.exs:2`, `page_controller_test.exs:2`. — both flipped; green.
- [x] Context tests + fixtures: `Bbh.Media` (+ `media_fixtures`), `Bbh.Notifications`
      (+ `notifications_fixtures`), `Bbh.Contact` (incl. altcha integration path). — `media_test.exs` (reuses existing `ContentFixtures.upload_fixture`; no separate media_fixtures needed), `notifications_test.exs` + new `notifications_fixtures.ex`, `contact_test.exs`. Altcha integration covered at controller level (see below).
- [x] Admin LiveView tests: article/event/location/media/page/person/user CRUD + dashboard —
      mount/render, `handle_event` save/delete/validate, and authorization (require authenticated + admin).
      Also `user_live/totp.ex`. — one file per resource under `test/bbh_web/live/admin/` + `authorization_test.exs` (unauth redirect for every admin route; editor blocked from `/benutzer`) + `dashboard_live_test.exs` (async_result) + `user_live/totp_test.exs` (sudo-mode redirect, enable/disable). Also fixed a missing form `id` on the set_role row form.
- [x] Public controller tests: article, event, contact (form + altcha), media, page_content, sitemap
      (XML), throne, totp, `api/push`. — all added under `test/bbh_web/controllers/`. 111 new tests total; full suite 243 green, format + `--warnings-as-errors` clean.

---

## Risks / self-check
- **Migration edit-in-place assumption** — safe only if branch is undeployed. Confirmed all migrations
  dated 2026-07-13; verify no shared/staging DB has run them before `ecto.reset`.
- **Altcha replay cache** — needs a store surviving across requests (ETS/Cachex); confirm no clustered
  deploy (single container per compose → in-memory fine).
- **Sanitization scope** — `HtmlSanitizeEx.basic_html/1` may strip Trix formatting classes; pick/tune a
  scrubber that preserves Trix output (headings, lists, links, bold/italic) while dropping scripts/handlers.

## Deferred (from triage — not in this plan, tracked in review-triage.md)
Path.safe_relative, contact-name CR/LF strip, TOTP `:since`, composite indexes, `_` escaping, decimal
lat/lng, ordinal unique constraint, Caddy tls email/headers, backup.sh volume/integrity, `.env.example`
docs, JSON logging + error tracking, rescue narrowing, import-task boot, cond→pattern-match style,
migration-safety review.

## Skipped
- `list_thrones per_page: 1` — intentional (one throne shown per page).

## Open question (unresolved)
- Confirm the flat admin role model (no per-resource ownership authz). Plan assumes YES.
