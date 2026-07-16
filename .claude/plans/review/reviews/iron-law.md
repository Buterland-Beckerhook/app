# Iron Law Violations Report

## Summary
- Files scanned: ~45 new `app/lib` files (LiveViews, controllers, contexts, mix task)
- Iron Laws checked: 12 of 26 (LiveView mount/DB, streams, PubSub, float-money, query pinning,
  has_many joins, atom creation, raw/XSS, Mix task boot, error-value handling, path traversal)
- Violations found: 10 (0 critical/BLOCKER, 4 high/WARNING, 6 medium/SUGGESTION)

Note: admin area is properly gated in `router.ex` (`require_authenticated_user` /
`require_admin` on_mount hooks), so no BLOCKER-level authz gaps found. All
`{:error, changeset}` clauses in form LiveViews are matched explicitly (Iron Law #17 OK).
No `:float` money fields (only legit `lat`/`lng`/`focal_point` floats). No `String.to_atom`
in `lib/`. No SQL fragment interpolation found.

## High Violations (WARNING)

### [#1] No unconditional DB queries in mount — repeated across all admin index/dashboard LiveViews
- **File**: `app/lib/bbh_web/live/admin/article_live/index.ex:7-9`, same pattern in
  `event_live/index.ex:7-9`, `person_live/index.ex:8-9`, `location_live/index.ex:7-9`,
  `page_live/index.ex:7-9`, `media_live/index.ex:7-19`, `user_live/index.ex:11-17`,
  `dashboard_live.ex:5-14`
- **Code**: `{:ok, assign(socket, page_title: "...", articles: Content.list_articles())}` — no
  `connected?` guard, no `assign_async`, no cache.
- **Confidence**: LIKELY (mount runs twice: HTTP + WebSocket connect → 2x DB load per page
  view). Severity mitigated somewhat because these are auth-gated admin routes with small
  result sets, not public SEO routes, so it's WARNING not BLOCKER.
- **Fix**: Wrap loads in `assign_async`, or at minimum keep as-is if list sizes stay small
  (a handful of rows) — but flag intent explicitly with a comment if accepted as a
  deliberate tradeoff. `dashboard_live.ex` additionally does 3 separate `Repo.aggregate`
  calls in mount — same doubling concern.

### [#2] Streams for large lists — `MediaLive.Index` uses plain assign for a growing collection
- **File**: `app/lib/bbh_web/live/admin/media_live/index.ex:11,28,54-58`
- **Code**: `assign(items: Media.list_uploads())` re-fetches and reassigns the full list on
  every filter/upload/delete instead of `stream(socket, :items, ...)`.
- **Confidence**: REVIEW — media library will grow unbounded over time (all site images);
  current pattern is O(n) per-connection memory and full re-render on every mutation.
- **Fix**: `stream(socket, :items, Media.list_uploads())`, `stream_insert`/`stream_delete` on
  upload/delete instead of reassigning the whole collection.

### [#3] Mix task boots the full app tree
- **File**: `app/lib/mix/tasks/bbh.import.ex:24`
- **Code**: `Mix.Task.run("app.start")`
- **Confidence**: DEFINITE — boots endpoint (binds port) and any configured job queue
  consumers unnecessarily for a one-off data-import task.
- **Fix**: `Mix.Task.run("app.config")` + `Application.ensure_all_started(:bbh)` +
  `Bbh.Repo.start_link()`. Lower real-world impact since the module docstring marks this
  as throwaway ("run once at cutover, then delete this task"), but fix is trivial.

### [#4] Ignored mailer return value in contact form
- **File**: `app/lib/bbh_web/controllers/contact_controller.ex:18`
- **Code**: `_ = Bbh.Contact.deliver(data)` then unconditionally shows a success flash.
- **Confidence**: LIKELY — if Swoosh/SMTP delivery fails (mailer down, misconfigured), the
  visitor is told "Vielen Dank! Ihre Nachricht wurde gesendet." even though nothing was sent,
  and there is no logging of the failure.
- **Fix**: `case Bbh.Contact.deliver(data) do {:ok, _} -> ...; {:error, reason} -> Logger.error(...); still show generic success or a retry message end`.

## Medium Violations (SUGGESTION)

### [#5] Unsanitized rich-text HTML rendered with `raw/1`
- **File**: `app/lib/bbh_web/controllers/article_html/show.html.heex:33`,
  `app/lib/bbh_web/controllers/event_html/show.html.heex:45`,
  `app/lib/bbh_web/components/site_components.ex:183,190,214`
- **Code**: `{Phoenix.HTML.raw(@article.body)}` / `{Phoenix.HTML.raw(@block.body)}` — body is
  Trix-editor HTML stored verbatim and rendered raw to the public site with no server-side
  sanitization pass (no `HtmlSanitizeEx` or scrubber found in the codebase).
  Note: `totp.ex:85` `raw(@qr)` is fine (server-generated SVG, not user input).
- **Confidence**: REVIEW — content is admin/editor-authored, not anonymous public input, so
  risk is lower than classic stored-XSS, but any compromised or malicious editor account (or
  a pasted snippet from an untrusted source) becomes a site-wide XSS vector with no
  defense-in-depth.
- **Fix**: Sanitize `body` server-side on save (`HtmlSanitizeEx.basic_html/1` or a Trix-aware
  scrubber) rather than trusting raw storage + raw render.

### [#6] Naive path-traversal guard instead of `Path.safe_relative/2`
- **File**: `app/lib/bbh/media.ex:151-153`
- **Code**: `defp safe_source(key), do: if String.contains?(key, ".."), do: :error, else: {:ok, Path.join(uploads_dir(), key)}`
- **Confidence**: REVIEW — substring-based `..` rejection is generally effective here since
  Phoenix has already decoded the path segments, but it's a hand-rolled check rather than the
  stdlib primitive designed for this exact purpose.
- **Fix**: `Path.safe_relative(key, uploads_dir())` per the security skill's canonical pattern.

### [#7] No rate limiting on TOTP code guesses
- **File**: `app/lib/bbh_web/controllers/totp_controller.ex:12-26`
- **Confidence**: REVIEW — `create/2` checks `Accounts.valid_user_totp?/2` with no attempt
  counter/lockout/backoff; a 6-digit TOTP is brute-forceable over an unthrottled session
  window (session persists via `:totp_pending_user_id`).
- **Fix**: Add attempt counting (e.g., cap attempts per pending session, exponential backoff,
  or reuse `Hammer`/rate-limit patterns from the security skill).

### [#8] Admin-authored content still lacks per-`handle_event` re-authorization
- **File**: `app/lib/bbh_web/live/admin/article_live/form.ex` (`save_image`, `delete_image`,
  `save_throne`, `delete_throne`), `app/lib/bbh_web/live/admin/user_live/index.ex`
  (`set_role`, `delete`)
- **Confidence**: REVIEW — router/live_session gates the whole mount via
  `require_authenticated`/`require_admin`, so this is likely acceptable (no per-action
  authorization needed since any authenticated editor may manage all content by design), but
  flagging per the Iron Law's "re-authorize in every handle_event" default for human
  confirmation that the flat editor/admin role model is intentional and no per-resource
  ownership check was meant to exist.

### [#9] `String` vs binary_id comparison relies on implicit string form (works, but fragile)
- **File**: `app/lib/bbh_web/live/admin/user_live/index.ex:45`
- **Code**: `if id == socket.assigns.current_scope.user.id`
- **Confidence**: REVIEW (informational) — `User.id` is `:binary_id` (string UUID) so the
  comparison against the string `id` param is correct today; flagging only because it's a
  silent footgun if the PK type ever changes.

### [#10] Pre-existing/out-of-scope
- One-liner: `app/lib/bbh/notifications.ex:67` and `app/lib/bbh/altcha.ex:45` use bare
  `rescue`, but both are narrowly scoped (external HTTP/crypto calls) and log/return safe
  defaults — acceptable per Iron Law #5 ("rescue only for external code"), not flagged as a
  violation.
