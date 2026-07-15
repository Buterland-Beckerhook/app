# Scratchpad — phoenix-rewrite review fixes

## Source
Plan built from `.claude/plans/review/reviews/review-triage.md` (interactive triage of
the 8-agent `/phx:review` of branch `feat/phoenix-rewrite`). No research agents spawned —
review findings are the research (plan Iron Law #7).

## Key decisions (from user triage)
- **DB SSL**: keep OFF, document as accepted risk (internal Docker/Compose network). No TLS certs.
- **Rate limiting**: add `hammer` dep; single limiter module reused for TOTP/login/magic-link/push.
- **Trix sanitization**: add `html_sanitize_ex`; sanitize `@body` on save in changesets (store clean HTML).
- **list_thrones per_page: 1** → intentional (one throne per page). NOT changed.

## Assumptions (override if wrong)
- Branch NOT yet deployed (all migrations dated 2026-07-13, brand new). Therefore migration
  fixes (thrones on_delete, FK indexes) are edited **in place** + `mix ecto.reset`, rather than
  adding alter-migrations. If any environment already ran these migrations, switch to a new
  alter migration instead.
- Admin role model is intentionally flat (editor/admin), gated at mount via `require_admin`;
  no per-resource ownership checks needed. (Open question from triage — assumed YES.)

## Deferred (tracked in triage file, not in this plan)
SUGGESTION-level nits: Path.safe_relative, contact name CR/LF, TOTP :since, composite indexes,
`_` escaping, decimal lat/lng, ordinal unique constraint, Caddy tls email, backup.sh checks,
.env docs, JSON logging/error tracking, rescue narrowing, import task boot, cond→match style.

## Notes
- (prior stale API-failure markers cleared 2026-07-14)

## COMPLETE — 2026-07-14
All 30 tasks / 7 phases done. Final state: `mix compile --warnings-as-errors`, `mix format`,
and `mix test` (243 passing, up from 132) all green.
- Phase 5: dashboard + article-media-picker converted to `assign_async`/`<.async_result>`.
  media-streams / Task.Supervisor / user self+last-admin guards were already satisfied in code.
- Phase 6: +111 tests — 3 context suites (media/notifications/contact, + `notifications_fixtures`),
  9 admin LiveView suites + authorization + dashboard + totp, 9 public controller suites.
  Reused existing `ContentFixtures.upload_fixture` instead of a separate media_fixtures.
  Fixed a missing `id` on the set_role row form (removed a LiveView form-recovery warning).
- User confirmed nothing is deployed → Phase 1 migration edit-in-place risk is moot.
- Still open (assumed YES, unchanged): flat admin role model (no per-resource ownership authz).

## API Failure — 2026-07-15 15:10

Turn ended due to API error. Check progress.md for last completed task.
Resume with: /phx:work --continue
